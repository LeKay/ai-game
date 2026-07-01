## CameraController — Camera pan, zoom, and boundary clamping.
## Core layer. Processes WASD/arrow key pan, middle mouse drag, edge scrolling, scroll wheel zoom,
## and world-boundary clamping. Input gated on InputContext.WORLD_ACTIVE context (context value 0).

class_name CameraController extends Camera2D

const TILE_SIZE: int = 64
const GRID_SIZE: int = 30
const WORLD_ACTIVE_CONTEXT: int = 0
const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 2.0
const INITIAL_ZOOM_TICKS: int = 6
const _PAN_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]

## Pan speed in tiles per second.
var pan_speed_tiles_per_second: float = 8.0
## Pixels from screen edge that trigger edge scrolling.
var edge_zone_width: int = 20
## Zoom speed multiplier applied to scroll wheel factor.
var zoom_sensitivity: float = 0.05

var _input_context: Node = null
var _held_directions: Dictionary[StringName, bool] = {}
var _mouse_inside_window: bool = true
var _middle_drag_active: bool = false

## Test seam: overrides get_visible_rect().size when non-zero. Set before add_child().
var _screen_size_override: Vector2 = Vector2.ZERO
## Test seam: overrides get_mouse_position() when x >= 0. Set before add_child().
var _mouse_pos_override: Vector2 = Vector2(-1.0, -1.0)
## Test seam: overrides gui_get_hovered_control() result. Active when _screen_size_override is set.
var _ui_hovered_override: bool = false


func _ready() -> void:
	anchor_mode = ANCHOR_MODE_FIXED_TOP_LEFT
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	fit_to_view()


func _enter_tree() -> void:
	if _input_context == null:
		_input_context = get_node_or_null("/root/InputContext")
		if _input_context == null:
			push_warning("CameraController: InputContext singleton not found")
	if _input_context != null:
		_input_context.context_changed.connect(_on_context_changed)
	var dispatcher: Node = get_node_or_null("/root/InputDispatcher")
	if dispatcher != null:
		dispatcher.action_pressed.connect(_on_action_pressed)
		dispatcher.action_released.connect(_on_action_released)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.disconnect(_on_viewport_size_changed)
	if _input_context != null and _input_context.context_changed.is_connected(_on_context_changed):
		_input_context.context_changed.disconnect(_on_context_changed)
	var dispatcher: Node = get_node_or_null("/root/InputDispatcher")
	if dispatcher != null:
		if dispatcher.action_pressed.is_connected(_on_action_pressed):
			dispatcher.action_pressed.disconnect(_on_action_pressed)
		if dispatcher.action_released.is_connected(_on_action_released):
			dispatcher.action_released.disconnect(_on_action_released)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_EXIT:
			_mouse_inside_window = false
			_middle_drag_active = false
		NOTIFICATION_WM_MOUSE_ENTER:
			_mouse_inside_window = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_drag_active = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _input_context != null and _input_context.get_current() == WORLD_ACTIVE_CONTEXT:
				var delta: float = mb.factor if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -mb.factor
				_apply_zoom(delta)
				_apply_boundary_clamp()
				get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		if _input_context != null and _input_context.get_current() == WORLD_ACTIVE_CONTEXT:
			var mg := event as InputEventMagnifyGesture
			# Mac trackpad pinch: convert multiplicative factor into the additive delta
			# that _apply_zoom expects (delta * zoom_sensitivity is added to zoom.x).
			var delta: float = (mg.factor - 1.0) / zoom_sensitivity
			_apply_zoom(delta)
			_apply_boundary_clamp()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _middle_drag_active:
			var motion := event as InputEventMouseMotion
			position -= motion.relative / zoom.x
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CAMERA_RESET):
		if _input_context != null and _input_context.get_current() == WORLD_ACTIVE_CONTEXT:
			fit_to_view()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _input_context == null:
		return
	if _input_context.get_current() != WORLD_ACTIVE_CONTEXT:
		return
	_apply_key_pan(delta)
	_apply_edge_scroll(delta)
	_apply_boundary_clamp()


func _apply_key_pan(delta: float) -> void:
	var pan_pixels: float = pan_speed_tiles_per_second * TILE_SIZE * delta
	var dir := Vector2.ZERO
	if _held_directions.get(&"move_up", false):
		dir.y -= 1.0
	if _held_directions.get(&"move_down", false):
		dir.y += 1.0
	if _held_directions.get(&"move_left", false):
		dir.x -= 1.0
	if _held_directions.get(&"move_right", false):
		dir.x += 1.0
	position += dir * pan_pixels


func _apply_edge_scroll(delta: float) -> void:
	if not _mouse_inside_window:
		return
	if _is_over_ui():
		return
	var mouse_pos: Vector2 = _get_mouse_pos()
	var screen_size: Vector2 = _get_screen_size()
	if screen_size == Vector2.ZERO:
		return
	var edge_speed: float = pan_speed_tiles_per_second * 0.25 * TILE_SIZE * delta
	var dir := Vector2.ZERO
	if mouse_pos.x < edge_zone_width:
		dir.x -= 1.0
	elif mouse_pos.x > screen_size.x - edge_zone_width:
		dir.x += 1.0
	if mouse_pos.y < edge_zone_width:
		dir.y -= 1.0
	elif mouse_pos.y > screen_size.y - edge_zone_width:
		dir.y += 1.0
	position += dir * edge_speed


func _is_over_ui() -> bool:
	if _screen_size_override != Vector2.ZERO:
		return _ui_hovered_override
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.gui_get_hovered_control() != null


func _get_mouse_pos() -> Vector2:
	if _mouse_pos_override.x >= 0.0:
		return _mouse_pos_override
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_mouse_position()


func _get_screen_size() -> Vector2:
	if _screen_size_override != Vector2.ZERO:
		return _screen_size_override
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_visible_rect().size


## Applies a zoom delta anchored to the current mouse screen position.
## Anchor formula keeps the world tile under the cursor fixed after zoom.
func _apply_zoom(scroll_delta: float) -> void:
	if scroll_delta == 0.0:
		return
	var current_scalar: float = zoom.x
	var new_scalar: float = clamp(current_scalar + scroll_delta * zoom_sensitivity, MIN_ZOOM, MAX_ZOOM)
	if new_scalar == current_scalar:
		return
	var mouse_screen: Vector2 = _get_mouse_pos()
	var mouse_world_before: Vector2 = (mouse_screen / current_scalar) + position
	position = mouse_world_before - (mouse_screen / new_scalar)
	zoom = Vector2(new_scalar, new_scalar)


## Clamps camera position so the map cannot fully leave the screen.
## Allows panning at most half a viewport's worth of world-space beyond each map edge
## (soft boundary — same behaviour as the overworld view).
func _apply_boundary_clamp() -> void:
	var screen: Vector2 = _get_screen_size()
	if screen == Vector2.ZERO:
		return
	var scalar: float = zoom.x
	var max_world: float = float(GRID_SIZE * TILE_SIZE)
	var view_width: float = screen.x / scalar
	var view_height: float = screen.y / scalar
	var pad_x: float = view_width * 0.5
	var pad_y: float = view_height * 0.5
	position.x = clamp(position.x, -pad_x, max_world - view_width + pad_x)
	position.y = clamp(position.y, -pad_y, max_world - view_height + pad_y)


## Converts a screen-space position to the nearest tile coordinate.
## Pure query — no side effects. Callable from any context.
## Out-of-range inputs are clamped to [0, GRID_SIZE-1].
func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos: Vector2 = position + screen_pos / zoom
	var tile := Vector2i(
		floori(world_pos.x / TILE_SIZE),
		floori(world_pos.y / TILE_SIZE)
	)
	return tile.clamp(Vector2i(0, 0), Vector2i(GRID_SIZE - 1, GRID_SIZE - 1))


## Zooms to INITIAL_ZOOM_TICKS ticks in from the full-map fit zoom.
## Positions camera at top-left (0,0); map is scrollable vertically.
## Called on startup and bound to the camera_reset action (R key).
func fit_to_view() -> void:
	var screen: Vector2 = _get_screen_size()
	if screen == Vector2.ZERO:
		return
	var max_world: float = float(GRID_SIZE * TILE_SIZE)
	var fit_zoom: float = clamp(screen.x / max_world, MIN_ZOOM, MAX_ZOOM)
	var start_zoom: float = clamp(fit_zoom + INITIAL_ZOOM_TICKS * zoom_sensitivity, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(start_zoom, start_zoom)
	position = Vector2.ZERO
	_apply_boundary_clamp()


## Converts a tile coordinate to the tile-centre screen position.
## Pure query — no side effects. Callable from any context.
func tile_to_screen(tile_pos: Vector2i) -> Vector2:
	var world_pos: Vector2 = Vector2(tile_pos) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) / 2.0
	return (world_pos - position) * zoom


func _on_viewport_size_changed() -> void:
	_apply_boundary_clamp()


func _on_context_changed(new_context: int) -> void:
	if new_context != WORLD_ACTIVE_CONTEXT:
		_held_directions.clear()
		_middle_drag_active = false


func _on_action_pressed(action: StringName) -> void:
	if action in _PAN_ACTIONS:
		_held_directions[action] = true


func _on_action_released(action: StringName) -> void:
	_held_directions.erase(action)


func serialize() -> Dictionary:
	return {"position_x": position.x, "position_y": position.y, "zoom": zoom.x}


func deserialize(data: Dictionary) -> void:
	position = Vector2(float(data.get("position_x", 0.0)), float(data.get("position_y", 0.0)))
	var z: float = clampf(float(data.get("zoom", zoom.x)), MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	_apply_boundary_clamp()
