extends Control
## OverworldView — full-screen, toggleable render layer for the OverworldSystem island.
## Slice 3 of the overworld spec: draws the biome grid at small RimWorld-style tiles with
## its own pan/zoom (independent of the tactical Camera2D), a hover highlight, and the start
## tile marker. Opening pushes UI_ACTIVE so the world camera stops; closing pops it.
## Toggle with the `overworld_toggle` action (M) or close with ui_cancel (Esc).
## Spec: design/quick-specs/overworld-map-system-2026-06-21.md

## Biome fill colors (ocean / coast / inland).
const _COLOR_OCEAN := Color(0.12, 0.32, 0.55)
const _COLOR_COAST := Color(0.85, 0.78, 0.55)
const _COLOR_INLAND := Color(0.30, 0.55, 0.28)
const _COLOR_BACKDROP := Color(0.05, 0.08, 0.12)
const _COLOR_GRID := Color(0.0, 0.0, 0.0, 0.15)
const _COLOR_START := Color(1.0, 0.84, 0.0)        ## Gold border on the chosen start tile.
const _COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.7)

const _MIN_ZOOM: float = 1.0
const _MAX_ZOOM: float = 10.0
const _ZOOM_STEP: float = 1.15                     ## Multiplicative per wheel notch.
const _FIT_MARGIN: float = 0.85                    ## Island fills this fraction of the screen.

## World-space (overworld pixels) position shown at the view's top-left, and the pixel scale.
var _view_offset: Vector2 = Vector2.ZERO
var _view_zoom: float = 1.0
var _dragging: bool = false
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _open: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# Redraw when the overworld regenerates or a start tile is chosen.
	OverworldSystem.overworld_generated.connect(queue_redraw)
	OverworldSystem.start_selected.connect(func(_c: Vector2i) -> void: queue_redraw())


# --- Toggle / open / close ---------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.OVERWORLD_TOGGLE):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed(InputActions.UI_CANCEL):
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


func open() -> void:
	if _open:
		return
	if not OverworldSystem.is_generated():
		# Until the start flow (Slice 4) drives generation, seed it on first open so there
		# is always something to inspect.
		OverworldSystem.generate(randi())
	_open = true
	visible = true
	InputContext.push_context(InputContext.Context.UI_ACTIVE)
	_fit_to_view()
	queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_dragging = false
	InputContext.pop_context()


# --- Pan / zoom / hover ------------------------------------------------------

func _handle_view_input(event: InputEvent) -> void:
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
			else:
				_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
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


# --- Rendering ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _COLOR_BACKDROP)
	if not OverworldSystem.is_generated():
		return
	var n: int = OverworldSystem.OVERWORLD_SIZE
	var ts: int = OverworldSystem.OVERWORLD_TILE_SIZE
	var px: float = ts * _view_zoom
	for x in range(n):
		for y in range(n):
			var coord := Vector2i(x, y)
			var screen_pos: Vector2 = (Vector2(coord * ts) - _view_offset) * _view_zoom
			var rect := Rect2(screen_pos, Vector2(px, px))
			draw_rect(rect, _biome_color(OverworldSystem.get_biome(coord)))
			if px >= 6.0:
				draw_rect(rect, _COLOR_GRID, false, 1.0)
	# Start tile marker.
	var start: Vector2i = OverworldSystem.get_start_coord()
	if start != Vector2i(-1, -1):
		draw_rect(_tile_rect(start, ts), _COLOR_START, false, maxf(2.0, px * 0.12))
	# Hover highlight (only on selectable land).
	if OverworldSystem.is_selectable(_hover_tile):
		draw_rect(_tile_rect(_hover_tile, ts), _COLOR_HOVER, false, 2.0)


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
