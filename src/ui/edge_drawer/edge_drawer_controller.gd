class_name EdgeDrawerController extends Node
## Generic right-edge slide-in drawer controller.
##
## Manages tab-nudge hover feedback, click-to-pin open/close, ESC routing, and
## the slide animation for any content node that extends [DrawerContentBase].
##
## Open/close model (NEW — differs from legacy hover-peek drawers):
##   - Idle:              Tab sits at the right edge; panel is fully off-screen.
##   - Hover over tab:    Tab nudges ~hover_peek_distance px leftward (visual feedback).
##                        Panel does NOT open on hover.
##   - Click tab:         Panel slides in (pinned = true).
##   - Click outside:     Panel slides out. The click event is NOT consumed — it
##                        passes through to the map beneath.
##   - ESC:               Offers event to content first (wants_escape_handled /
##                        handle_escape); falls back to closing the drawer.
##
## Layer registry: a static list tracks which layer_index values currently have
## open drawers so their z_index can be managed if needed.
##
## Setup (called once by the owning scene or HUD):
##   controller.setup(my_content_control, my_config, my_canvas_layer)

# --- Slide constants (shared geometry, matches legacy drawers) -----------------
const TAB_WIDTH := 44.0
const SLIDE_TIME := 0.2
const PEEK_ANIMATION_SPEED := 10.0

const PANEL_COLOR := Color(0.12, 0.13, 0.16, 1.0)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)

## Added to layer_index while the drawer is open so the panel covers all closed-drawer tabs.
const OPEN_LAYER_BOOST := 100

# --- Layer registry -----------------------------------------------------------
## Tracks layer_index values of currently open drawers. The last element in
## the array has the topmost z_index (highest stacking priority).
static var _open_layers: Array[int] = []

# --- Instance state -----------------------------------------------------------
var _config: EdgeDrawerConfig
var _canvas_layer: CanvasLayer
var _content: DrawerContentBase

var _slider: Control           # moving group [tab | panel], anchored to the right edge
var _tab: EdgeDrawerTab
var _panel_container: PanelContainer

var _slide := 0.0              # 0.0 = closed (panel off-screen), 1.0 = open
var _pinned := false           # true while the panel is clicked open
var _slide_tween: Tween

# Hover-peek state
var _tab_hovered := false
var _peek_offset := 0.0        # current leftward nudge applied to the tab (px)
var _peek_target := 0.0        # target nudge (0 or hover_peek_distance)


# --- Public API ---------------------------------------------------------------

## Wires the controller to a content node, a config resource, and the CanvasLayer
## that hosts everything. Call once before the node enters the tree (or in _ready
## of the owning scene right after instantiation).
func setup(content: DrawerContentBase, config: EdgeDrawerConfig, canvas_layer: CanvasLayer) -> void:
	_content = content
	_config = config
	_canvas_layer = canvas_layer
	_canvas_layer.layer = config.layer_index

	_build_ui()
	_apply_slide(0.0)
	set_process(true)

	# Forward content's request_close signal (guaranteed by DrawerContentBase).
	_content.request_close.connect(close)


## Slides the panel in and marks it pinned.
func open() -> void:
	if _pinned:
		return
	_pinned = true
	_canvas_layer.layer = _config.layer_index + OPEN_LAYER_BOOST
	_register_open_layer()
	_animate_slide(1.0)
	if _content != null:
		_content.on_drawer_opened()


## Slides the panel out and unpins it.
func close() -> void:
	if not _pinned:
		return
	_pinned = false
	_canvas_layer.layer = _config.layer_index
	_unregister_open_layer()
	_animate_slide(0.0)
	if _content != null:
		_content.on_drawer_closed()


## Toggles between open and closed.
func toggle() -> void:
	if _pinned:
		close()
	else:
		open()


## Returns true when the panel is currently pinned open.
func is_open() -> bool:
	return _pinned


## Returns true when the panel is open and the viewport mouse position is inside it.
func is_mouse_over_panel() -> bool:
	if not _pinned or _panel_container == null:
		return false
	return _panel_container.get_global_rect().has_point(get_viewport().get_mouse_position())


## Delegates badge display to the EdgeDrawerTab.
func set_badge(text: String, color: Color) -> void:
	if _tab != null:
		_tab.set_badge(text, color)


# --- Input handling -----------------------------------------------------------

## True while a full-screen modal that must block drawer auto-close is showing (e.g. the perk
## choice panel opened from a detail view). Such modals join the group and expose is_showing().
func _is_blocking_modal_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"blocks_edge_drawer_autoclose"):
		if node.has_method("is_showing") and node.is_showing():
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not _pinned:
		return
	# A blocking modal (e.g. perk choice) owns ESC while it is up — don't let it close the drawer.
	if _is_blocking_modal_open():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return

	# Let content intercept ESC first if it wants it.
	if _content != null and _content.wants_escape_handled():
		if _content.handle_escape():
			get_viewport().set_input_as_handled()
			return

	close()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _pinned:
		return
	# While a blocking modal (e.g. the perk choice panel) is up, ignore outside-clicks so selecting
	# a card / clicking the overlay does not auto-close the drawer beneath it.
	if _is_blocking_modal_open():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# Determine whether the click is inside the slider (tab + panel area).
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var inside_slider: bool = _slider != null and _slider.get_global_rect().has_point(mouse_pos)
	if inside_slider:
		return

	# Click is outside — close but do NOT consume the event so the map receives it.
	close()
	# Intentionally NOT calling set_input_as_handled() here.


# --- Process: hover-peek animation -------------------------------------------

func _process(delta: float) -> void:
	if _config == null or _tab == null:
		return

	_peek_target = _config.hover_peek_distance if _tab_hovered else 0.0

	# Lerp the tab nudge for smooth visual feedback.
	_peek_offset = lerp(_peek_offset, _peek_target, clampf(PEEK_ANIMATION_SPEED * delta, 0.0, 1.0))

	# Apply the nudge to the tab portion of the slider only.
	# The slider itself stays anchored; we shift the tab's left position
	# by adjusting offset_left of the slider, which shifts both tab and panel.
	# To nudge only the tab, we directly offset the tab node's position.
	if _tab != null:
		_tab.position.x = -_peek_offset


# --- Slide animation ---------------------------------------------------------

func _animate_slide(target: float) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_method(_apply_slide, _slide, target, SLIDE_TIME)


## Positions the slider so t=0 leaves only the tab visible at the right edge
## and t=1 brings the full panel on-screen.
## Formula mirrors the legacy drawers exactly:
##   offset_left  = lerp(-TAB_WIDTH, -(TAB_WIDTH + panel_width), t)
##   offset_right = lerp(panel_width, 0.0, t)
func _apply_slide(t: float) -> void:
	_slide = t
	if _slider == null or _config == null:
		return
	_slider.offset_left = lerp(-TAB_WIDTH, -(TAB_WIDTH + _config.panel_width), t)
	_slider.offset_right = lerp(_config.panel_width, 0.0, t)


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	# The slider is a full-height strip anchored to the right edge of the
	# CanvasLayer's viewport. It contains [tab | panel] side-by-side.
	_slider = Control.new()
	_slider.name = "Slider"
	_slider.anchor_left = 1.0
	_slider.anchor_right = 1.0
	_slider.anchor_top = 0.0
	_slider.anchor_bottom = 1.0
	_slider.offset_top = 0.0
	_slider.offset_bottom = 0.0
	# IGNORE: the slider spans the full-height right strip; only tab and panel
	# (both STOP) should capture input — siblings beneath remain accessible.
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_slider)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slider.add_child(row)

	_tab = EdgeDrawerTab.new()
	_tab.name = "Tab"
	_tab.setup(_config)
	_tab.hover_entered.connect(_on_tab_hover_entered)
	_tab.hover_exited.connect(_on_tab_hover_exited)
	_tab.pressed.connect(toggle)
	row.add_child(_tab)

	_panel_container = _build_panel()
	row.add_child(_panel_container)


func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	panel.custom_minimum_size = Vector2(_config.panel_width, 0)
	# STOP: eat pointer events over the panel so they don't fall through to the map.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _build_panel_style())
	panel.gui_input.connect(_on_panel_gui_input)

	if _content != null:
		_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(_content)

	return panel


# --- Tab hover callbacks ------------------------------------------------------

func _on_tab_hover_entered() -> void:
	_tab_hovered = true


func _on_tab_hover_exited() -> void:
	_tab_hovered = false


## Swallows scroll-wheel events over the panel so they don't propagate to the
## camera-zoom handler beneath.
func _on_panel_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and (mb.button_index == MOUSE_BUTTON_WHEEL_UP \
			or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		get_viewport().set_input_as_handled()


# --- Layer registry ----------------------------------------------------------

func _register_open_layer() -> void:
	if not _open_layers.has(_config.layer_index):
		_open_layers.append(_config.layer_index)


func _unregister_open_layer() -> void:
	_open_layers.erase(_config.layer_index)


# --- Styleboxes --------------------------------------------------------------

func _build_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.corner_radius_top_left = 12
	sb.corner_radius_bottom_left = 12
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 8
	return sb
