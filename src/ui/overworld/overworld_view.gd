extends Control
## OverworldView — full-screen, toggleable render layer for the OverworldSystem island.
## Draws the biome grid at small RimWorld-style tiles with its own pan/zoom (independent of
## the tactical Camera2D), a hover highlight, the start-tile marker, and a read-only tile
## inspection panel. Opening pushes UI_ACTIVE so the world camera stops; closing pops it.
##
## Two modes:
##  - Anytime layer (toggle with `overworld_toggle` / M): inspect tiles read-only.
##  - Start picker (open_for_pick(), used on a new game): the panel gains a "Start here"
##    button; committing emits OverworldSystem.start_selected and closes. The view cannot be
##    dismissed without choosing, so a new game always has a valid start tile.
## Spec: design/quick-specs/overworld-map-system-2026-06-21.md

## Biome fill colors (ocean / coast / inland).
const _COLOR_OCEAN := Color(0.12, 0.32, 0.55)
const _COLOR_COAST := Color(0.85, 0.78, 0.55)
const _COLOR_INLAND := Color(0.30, 0.55, 0.28)
const _COLOR_BACKDROP := Color(0.05, 0.08, 0.12)
const _COLOR_GRID := Color(0.0, 0.0, 0.0, 0.15)
const _COLOR_START := Color(1.0, 0.84, 0.0)        ## Gold border on the chosen start tile.
const _COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.7)
const _COLOR_SELECTED := Color(0.4, 0.85, 1.0)     ## Cyan border on the inspected tile.

const _MIN_ZOOM: float = 0.1   ## Low enough to fit the whole 256-tile island on screen.
const _MAX_ZOOM: float = 10.0
const _ZOOM_STEP: float = 1.15                     ## Multiplicative per wheel notch.
const _FIT_MARGIN: float = 0.85                    ## Island fills this fraction of the screen.
const _CLICK_MAX_TRAVEL: float = 6.0               ## Below this drag distance, a release is a click.
const _GRID_MIN_PX: float = 24.0                   ## Only draw tile grid lines once tiles are this big.

## Compass label per WorldGrid coast_edge (0 top, 1 bottom, 2 left, 3 right).
const _EDGE_COMPASS: Array[String] = ["North", "South", "West", "East"]

## World-space (overworld pixels) position shown at the view's top-left, and the pixel scale.
var _view_offset: Vector2 = Vector2.ZERO
var _view_zoom: float = 1.0
var _dragging: bool = false
var _drag_travel: float = 0.0                      ## Accumulated drag distance since press.
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _selected_tile: Vector2i = Vector2i(-1, -1)    ## Tile shown in the inspection panel.
var _open: bool = false
var _pick_mode: bool = false                       ## True while choosing a new game's start.

## One-pixel-per-tile biome image, drawn as a single nearest-filtered rect so rendering cost
## is independent of OVERWORLD_SIZE (a 256x256 grid is one draw call, not 65k).
var _biome_tex: ImageTexture = null

# Inspection panel widgets (built programmatically in _ready).
var _panel: PanelContainer = null
var _title_label: Label = null
var _biome_label: Label = null
var _fertility_label: Label = null
var _note_label: Label = null
var _start_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp tile edges when zoomed in
	visible = false
	_build_panel()
	# Rebuild the biome texture on (re)generation; redraw the marker on start selection.
	OverworldSystem.overworld_generated.connect(_on_overworld_generated)
	OverworldSystem.start_selected.connect(func(_c: Vector2i) -> void: queue_redraw())


func _on_overworld_generated() -> void:
	_biome_tex = null  # invalidate; rebuilt lazily on next draw
	queue_redraw()


## Builds the one-pixel-per-tile biome image. Cheap and done once per generation.
func _rebuild_biome_texture() -> void:
	var n: int = OverworldSystem.OVERWORLD_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for x in range(n):
		for y in range(n):
			img.set_pixel(x, y, _biome_color(OverworldSystem.get_biome(Vector2i(x, y))))
	_biome_tex = ImageTexture.create_from_image(img)


# --- Toggle / open / close ---------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.OVERWORLD_TOGGLE):
		# In pick mode the player must commit a start before the view can be dismissed.
		if not _pick_mode:
			toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and not _pick_mode and event.is_action_pressed(InputActions.UI_CANCEL):
		close()
		get_viewport().set_input_as_handled()
		return
	if _open:
		_handle_view_input(event)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Opens the anytime inspection layer.
func open() -> void:
	if _open:
		return
	if not OverworldSystem.is_generated():
		OverworldSystem.generate(randi())
	_open = true
	visible = true
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_fit_to_view()
	_hide_panel()
	queue_redraw()


## Opens the view as a blocking start picker (new game). Assumes the overworld is generated.
func open_for_pick() -> void:
	_pick_mode = true
	if _open:
		_hide_panel()
		queue_redraw()
		return
	open()


func close() -> void:
	if not _open:
		return
	if _pick_mode:
		return  # Must choose a start first.
	_open = false
	visible = false
	_dragging = false
	_hide_panel()
	InputContext.pop_context()


# --- Pan / zoom / hover / click ----------------------------------------------

func _handle_view_input(event: InputEvent) -> void:
	# Let the inspection panel handle events over its own rect (button clicks, etc.).
	if _panel.visible and event is InputEventMouse and _panel.get_global_rect().has_point((event as InputEventMouse).position):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_travel = 0.0
			else:
				_dragging = false
				if _drag_travel <= _CLICK_MAX_TRAVEL:
					_on_tile_clicked(_screen_to_tile(mb.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_drag_travel += mm.relative.length()
			_view_offset -= mm.relative / _view_zoom
			queue_redraw()
		var tile := _screen_to_tile(mm.position)
		if tile != _hover_tile:
			_hover_tile = tile
			queue_redraw()
		get_viewport().set_input_as_handled()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clampf(_view_zoom * factor, _MIN_ZOOM, _MAX_ZOOM)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	# Keep the world point under the cursor fixed while zooming.
	var world_before: Vector2 = _view_offset + screen_pos / _view_zoom
	_view_zoom = new_zoom
	_view_offset = world_before - screen_pos / _view_zoom
	queue_redraw()


func _fit_to_view() -> void:
	var world_px: float = float(OverworldSystem.OVERWORLD_SIZE * OverworldSystem.OVERWORLD_TILE_SIZE)
	var screen: Vector2 = size
	if screen == Vector2.ZERO or world_px <= 0.0:
		return
	var fit: float = minf(screen.x, screen.y) / world_px * _FIT_MARGIN
	_view_zoom = clampf(fit, _MIN_ZOOM, _MAX_ZOOM)
	# Center the island in the viewport.
	_view_offset = Vector2(world_px, world_px) * 0.5 - screen / (2.0 * _view_zoom)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world: Vector2 = _view_offset + screen_pos / _view_zoom
	var ts: int = OverworldSystem.OVERWORLD_TILE_SIZE
	return Vector2i(floori(world.x / ts), floori(world.y / ts))


## A tile was clicked (not dragged): select it and refresh the inspection panel.
func _on_tile_clicked(coord: Vector2i) -> void:
	if OverworldSystem.get_tile(coord) == null:
		_hide_panel()
		return
	_selected_tile = coord
	_populate_panel(coord)
	queue_redraw()


# --- Inspection panel --------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "InfoPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Pin to the top-right corner, content-sized, growing leftward/downward.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_right = -24
	_panel.offset_top = 24
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200, 0)
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_title_label = _make_label(vbox, 18)
	_biome_label = _make_label(vbox, 14)
	_fertility_label = _make_label(vbox, 14)
	_fertility_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label = _make_label(vbox, 13)
	_note_label.modulate = _COLOR_START

	_start_button = Button.new()
	_start_button.text = "Start here"
	_start_button.visible = false
	_start_button.pressed.connect(_on_start_here_pressed)
	vbox.add_child(_start_button)


func _make_label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _populate_panel(coord: Vector2i) -> void:
	var tile := OverworldSystem.get_tile(coord)
	if tile == null:
		_hide_panel()
		return
	_title_label.text = "Tile (%d, %d)" % [coord.x, coord.y]
	_biome_label.text = "Biome: %s" % _biome_text(tile)
	if tile.fertilities.is_empty():
		_fertility_label.text = "Open water — no land to settle."
	else:
		_fertility_label.text = "Fertilities: %s" % _fertility_text(tile.fertilities)
	_note_label.visible = tile.is_start
	_note_label.text = "Current start"
	# Offer the start button only while picking and only on land tiles.
	_start_button.visible = _pick_mode and OverworldSystem.is_selectable(coord)
	_panel.visible = true


func _hide_panel() -> void:
	if _panel != null:
		_panel.visible = false
	_selected_tile = Vector2i(-1, -1)


func _on_start_here_pressed() -> void:
	if not OverworldSystem.is_selectable(_selected_tile):
		return
	# Commit: this fires OverworldSystem.start_selected, which the map coordinator listens
	# for to generate the tactical map. Drop pick mode first so close() will proceed.
	var coord := _selected_tile
	_pick_mode = false
	_hide_panel()
	OverworldSystem.select_start(coord)
	close()


func _biome_text(tile) -> String:
	match tile.biome:
		OverworldSystem.Biome.INLAND:
			return "Inland"
		OverworldSystem.Biome.COAST:
			var dir: String = _EDGE_COMPASS[tile.coast_edge] if tile.coast_edge >= 0 else "?"
			return "Coast (faces %s)" % dir
		_:
			return "Ocean"


func _fertility_text(fertilities: Array) -> String:
	var parts: Array[String] = []
	for f in fertilities:
		parts.append(String(f).capitalize())
	return ", ".join(parts)


# --- Rendering ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _COLOR_BACKDROP)
	if not OverworldSystem.is_generated():
		return
	if _biome_tex == null:
		_rebuild_biome_texture()
	var n: int = OverworldSystem.OVERWORLD_SIZE
	var ts: int = OverworldSystem.OVERWORLD_TILE_SIZE
	var px: float = ts * _view_zoom
	# Whole biome grid as one nearest-filtered rect (1 draw call regardless of size).
	var map_origin: Vector2 = (Vector2.ZERO - _view_offset) * _view_zoom
	var map_size: float = n * ts * _view_zoom
	draw_texture_rect(_biome_tex, Rect2(map_origin, Vector2(map_size, map_size)), false)
	# Grid lines only when zoomed in enough to matter, and only over the visible tile range.
	if px >= _GRID_MIN_PX:
		var tl: Vector2i = _clamp_tile(_screen_to_tile(Vector2.ZERO))
		var br: Vector2i = _clamp_tile(_screen_to_tile(size))
		for x in range(tl.x, br.x + 1):
			for y in range(tl.y, br.y + 1):
				draw_rect(_tile_rect(Vector2i(x, y), ts), _COLOR_GRID, false, 1.0)
	# Start tile marker.
	var start: Vector2i = OverworldSystem.get_start_coord()
	if start != Vector2i(-1, -1):
		draw_rect(_tile_rect(start, ts), _COLOR_START, false, maxf(2.0, px * 0.12))
	# Inspected tile outline.
	if _selected_tile != Vector2i(-1, -1):
		draw_rect(_tile_rect(_selected_tile, ts), _COLOR_SELECTED, false, 2.0)
	# Hover highlight (only on selectable land).
	if OverworldSystem.is_selectable(_hover_tile):
		draw_rect(_tile_rect(_hover_tile, ts), _COLOR_HOVER, false, 2.0)


func _clamp_tile(coord: Vector2i) -> Vector2i:
	var n: int = OverworldSystem.OVERWORLD_SIZE
	return Vector2i(clampi(coord.x, 0, n - 1), clampi(coord.y, 0, n - 1))


func _tile_rect(coord: Vector2i, ts: int) -> Rect2:
	var screen_pos: Vector2 = (Vector2(coord * ts) - _view_offset) * _view_zoom
	return Rect2(screen_pos, Vector2(ts * _view_zoom, ts * _view_zoom))


func _biome_color(biome: int) -> Color:
	match biome:
		OverworldSystem.Biome.INLAND:
			return _COLOR_INLAND
		OverworldSystem.Biome.COAST:
			return _COLOR_COAST
		_:
			return _COLOR_OCEAN
