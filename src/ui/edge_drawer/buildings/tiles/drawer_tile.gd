class_name DrawerTile extends PanelContainer
## Base tile widget used in the Buildings Drawer.
## Displays a 72×84px card with a 56×56 icon (texture or glyph), a label, and an
## optional badge dot in the top-right corner. Supports disabled and active visual states.

signal pressed()
signal hovered()

enum TileState { NORMAL, HOVER, PRESSED, DISABLED, ACTIVE }

const TILE_SIZE := Vector2(72, 96)
const ICON_SIZE := Vector2(56, 56)

const COLOR_BG         := Color(0.14, 0.15, 0.18, 1.0)
const COLOR_BG_HOVER   := Color(0.20, 0.22, 0.27, 1.0)
const COLOR_BG_ACTIVE  := Color(0.18, 0.32, 0.42, 1.0)
const COLOR_BG_PRESSED := Color(0.12, 0.13, 0.15, 1.0)
const COLOR_LABEL      := Color(0.85, 0.85, 0.85, 1.0)

var _icon_texture:   TextureRect
var _icon_label:     Label        ## fallback glyph when no texture is set
var _name_label:     Label
var _badge_rect:     ColorRect
var _badge_label:    Label
var _progress_label: Label        ## placeholder for in-construction percentage
var _plus_label:     Label        ## "+" overlay
var _remove_btn:     Button       ## small red × in top-right corner (hidden by default)

var _state: TileState = TileState.NORMAL
var _is_new: bool = false

# Pending values stored when setters are called before _ready() / _build_layout().
var _pending_texture: Texture2D = null
var _pending_glyph:   String    = ""
var _pending_label:   String    = ""
var _pending_badge_text:  String = ""
var _pending_badge_color: Color  = Color.WHITE
var _pending_badge_set:   bool   = false  ## true once set_badge() has been called pre-ready


func _ready() -> void:
	custom_minimum_size = TILE_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style(TileState.NORMAL)
	_build_layout()
	# Apply any values that were set before _build_layout() created the child nodes.
	if _pending_texture != null:
		set_icon_texture(_pending_texture)
	elif _pending_glyph != "":
		set_icon_glyph(_pending_glyph)
	if _pending_label != "":
		set_label(_pending_label)
	if _pending_badge_set:
		set_badge(_pending_badge_text, _pending_badge_color)
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# --- Public API ---------------------------------------------------------------

## Displays a texture in the icon area; hides the glyph label.
func set_icon_texture(tex: Texture2D) -> void:
	if _icon_texture == null:
		_pending_texture = tex
		return
	_icon_texture.texture = tex
	_icon_texture.visible = tex != null
	_icon_label.visible   = tex == null


## Displays a text glyph (emoji or symbol) in the icon area; hides the texture.
func set_icon_glyph(glyph: String) -> void:
	if _icon_label == null:
		_pending_glyph = glyph
		return
	_icon_label.text      = glyph
	_icon_label.visible   = true
	_icon_texture.visible = false


## Sets the tile's name label text.
func set_label(text: String) -> void:
	if _name_label == null:
		_pending_label = text
		return
	_name_label.text = text


## Shows or hides a small circular badge in the top-right corner.
## Pass an empty string to hide it.
func set_badge(text: String, color: Color) -> void:
	if _badge_rect == null:
		_pending_badge_text  = text
		_pending_badge_color = color
		_pending_badge_set   = true
		return
	var show: bool = text != ""
	_badge_rect.visible  = show
	_badge_label.visible = show
	if show:
		_badge_rect.color = color
		_badge_label.text = text


## Sets the tile's visual state and re-styles accordingly.
func set_state(state: TileState) -> void:
	_state = state
	_apply_style(state)
	modulate.a = 0.4 if state == TileState.DISABLED else 1.0


## Shows or hides a gold outline that persists across hover/exit redraws.
## Used to mark building types that were recently unlocked.
func set_new_highlight(enabled: bool) -> void:
	_is_new = enabled
	_apply_style(_state)


## Shows a construction-progress label (0.0–1.0). Pass -1.0 to hide it.
func set_progress(value: float) -> void:
	if value < 0.0:
		_progress_label.visible = false
		return
	_progress_label.visible = true
	_progress_label.text    = "%d%%" % int(clampf(value, 0.0, 1.0) * 100.0)


## Shows or hides a "+" overlay glyph in the icon area.
func set_plus_glyph(enabled: bool) -> void:
	_plus_label.visible = enabled


## Shows a red × button in the top-right corner that calls [param callback] when pressed.
## Pass [param enabled] = false to hide it.
func set_remove_button(enabled: bool, callback: Callable = Callable()) -> void:
	if _remove_btn == null:
		return
	_remove_btn.visible = enabled
	# Disconnect any previous callback before connecting the new one.
	if _remove_btn.pressed.get_connections().size() > 0:
		for conn: Dictionary in _remove_btn.pressed.get_connections():
			_remove_btn.pressed.disconnect(conn["callable"])
	if enabled and callback.is_valid():
		_remove_btn.pressed.connect(callback)


# --- Layout construction ------------------------------------------------------

func _build_layout() -> void:
	## Root control fills the PanelContainer — we place all children here so the
	## badge overlay can be positioned absolutely without fighting Container layout.
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	## VBox holds icon + name label
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(vbox)

	## Icon area — fixed height container so glyph / texture / overlays are co-located
	var icon_wrapper := Control.new()
	icon_wrapper.name = "IconWrapper"
	icon_wrapper.custom_minimum_size    = Vector2(ICON_SIZE.x, ICON_SIZE.y)
	icon_wrapper.size_flags_horizontal  = Control.SIZE_SHRINK_CENTER
	icon_wrapper.size_flags_vertical    = Control.SIZE_SHRINK_BEGIN
	icon_wrapper.mouse_filter           = Control.MOUSE_FILTER_PASS
	vbox.add_child(icon_wrapper)

	_icon_texture = TextureRect.new()
	_icon_texture.name          = "IconTexture"
	_icon_texture.expand_mode   = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon_texture.stretch_mode  = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_texture.visible       = false
	icon_wrapper.add_child(_icon_texture)

	_icon_label = Label.new()
	_icon_label.name                 = "IconGlyph"
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 28)
	_icon_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_label.visible              = false
	icon_wrapper.add_child(_icon_label)

	_progress_label = Label.new()
	_progress_label.name                 = "ProgressLabel"
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	_progress_label.add_theme_font_size_override("font_size", 10)
	_progress_label.add_theme_color_override("font_color", Color(1.0, 0.596, 0.0))
	_progress_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress_label.visible             = false
	icon_wrapper.add_child(_progress_label)

	_plus_label = Label.new()
	_plus_label.name                 = "PlusGlyph"
	_plus_label.text                 = "+"
	_plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plus_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_plus_label.add_theme_font_size_override("font_size", 32)
	_plus_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.9))
	_plus_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plus_label.visible              = false
	icon_wrapper.add_child(_plus_label)

	## Name label beneath the icon
	_name_label = Label.new()
	_name_label.name                  = "NameLabel"
	_name_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", COLOR_LABEL)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter          = Control.MOUSE_FILTER_PASS
	vbox.add_child(_name_label)

	## Badge — 10×10 dot, absolute position top-right, sits in the root overlay
	_badge_rect = ColorRect.new()
	_badge_rect.name                = "BadgeRect"
	_badge_rect.custom_minimum_size = Vector2(10, 10)
	_badge_rect.anchor_left         = 1.0
	_badge_rect.anchor_top          = 0.0
	_badge_rect.anchor_right        = 1.0
	_badge_rect.anchor_bottom       = 0.0
	_badge_rect.offset_left         = -14
	_badge_rect.offset_top          = 4
	_badge_rect.offset_right        = -4
	_badge_rect.offset_bottom       = 14
	_badge_rect.visible             = false
	_badge_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	root.add_child(_badge_rect)

	_badge_label = Label.new()
	_badge_label.name                 = "BadgeLabel"
	_badge_label.visible              = false
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_badge_label.add_theme_font_size_override("font_size", 8)
	_badge_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badge_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_badge_rect.add_child(_badge_label)

	## Remove button — 14×14, top-right corner, hidden by default.
	_remove_btn = Button.new()
	_remove_btn.name    = "RemoveBtn"
	_remove_btn.text    = "×"
	_remove_btn.flat    = false
	_remove_btn.visible = false
	_remove_btn.focus_mode = Control.FOCUS_NONE
	_remove_btn.add_theme_font_size_override("font_size", 10)
	_remove_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	var rb_sb := StyleBoxFlat.new()
	rb_sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	rb_sb.border_width_left   = 1
	rb_sb.border_width_right  = 1
	rb_sb.border_width_top    = 1
	rb_sb.border_width_bottom = 1
	rb_sb.border_color = Color(1.0, 1.0, 1.0, 0.8)
	rb_sb.corner_radius_top_left     = 3
	rb_sb.corner_radius_top_right    = 3
	rb_sb.corner_radius_bottom_left  = 3
	rb_sb.corner_radius_bottom_right = 3
	rb_sb.content_margin_left   = 1
	rb_sb.content_margin_right  = 1
	rb_sb.content_margin_top    = 0
	rb_sb.content_margin_bottom = 0
	var rb_sb_hover := rb_sb.duplicate() as StyleBoxFlat
	rb_sb_hover.border_color = Color(1.0, 1.0, 1.0, 1.0)
	_remove_btn.add_theme_stylebox_override("normal",  rb_sb)
	_remove_btn.add_theme_stylebox_override("hover",   rb_sb_hover)
	_remove_btn.add_theme_stylebox_override("pressed", rb_sb)
	_remove_btn.custom_minimum_size = Vector2(16, 16)
	_remove_btn.anchor_left   = 1.0
	_remove_btn.anchor_top    = 0.0
	_remove_btn.anchor_right  = 1.0
	_remove_btn.anchor_bottom = 0.0
	_remove_btn.offset_left   = -18
	_remove_btn.offset_top    = 2
	_remove_btn.offset_right  = -2
	_remove_btn.offset_bottom = 18
	root.add_child(_remove_btn)


# --- Styling ------------------------------------------------------------------

func _apply_style(state: TileState) -> void:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left   = 4
	sb.content_margin_right  = 4
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 4
	match state:
		TileState.HOVER:
			sb.bg_color         = COLOR_BG_HOVER
			sb.border_width_left   = 1
			sb.border_width_right  = 1
			sb.border_width_top    = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.4, 0.6, 0.8, 0.6)
		TileState.PRESSED:
			sb.bg_color = COLOR_BG_PRESSED
		TileState.ACTIVE:
			sb.bg_color         = COLOR_BG_ACTIVE
			sb.border_width_left   = 2
			sb.border_width_right  = 2
			sb.border_width_top    = 2
			sb.border_width_bottom = 2
			sb.border_color = Color(0.3, 0.7, 1.0, 0.9)
		TileState.DISABLED:
			sb.bg_color = Color(COLOR_BG.r, COLOR_BG.g, COLOR_BG.b, 0.5)
		_:
			sb.bg_color = COLOR_BG
	if _is_new:
		sb.border_width_left   = 2
		sb.border_width_right  = 2
		sb.border_width_top    = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(1.0, 0.75, 0.0, 1.0)
	add_theme_stylebox_override("panel", sb)


# --- Input handlers -----------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		pressed.emit()


func _on_mouse_entered() -> void:
	hovered.emit()
	if _state == TileState.NORMAL:
		_apply_style(TileState.HOVER)


func _on_mouse_exited() -> void:
	_apply_style(_state)
