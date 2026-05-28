extends GdUnitTestSuite

## Tests for CameraController pan input (Story 001 — Pan Input).
## Covers AC-5 (WASD displacement), AC-6 (edge scroll displacement), AC-8 (mouse-leave guard).
##
## TILE_SIZE=64. pan_pixels = speed(8) * TILE_SIZE(64) * delta(0.01667) ≈ 8.534 px/frame.
## edge_speed = speed(8) * 0.25 * TILE_SIZE(64) * delta(0.01667) ≈ 2.134 px/frame.

var _camera: CameraController
var _mock_ctx: _MockContext

const _WORLD_ACTIVE: int = 0
const _UI_ACTIVE: int = 1


class _MockContext extends Node:
	var _current: int = 0

	func get_current() -> int:
		return _current


func before_test() -> void:
	_mock_ctx = _MockContext.new()
	_camera = CameraController.new()
	_camera._input_context = _mock_ctx
	_camera._screen_size_override = Vector2(800.0, 600.0)
	_camera._mouse_pos_override = Vector2(400.0, 300.0)
	add_child(_camera)
	add_child(_mock_ctx)


func after_test() -> void:
	_camera.queue_free()
	_mock_ctx.queue_free()
	_camera = null
	_mock_ctx = null


# --- AC-5: WASD pan displacement ---

## Right key held one frame → x increases by ~8.534 px.
func test_pan_wasd_right_key_displacement() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera._held_directions[&"move_right"] = true
	_camera._process(0.01667)
	assert_float(_camera.position.x).is_between(8.524, 8.544)
	assert_float(_camera.position.y).is_equal(0.0)


## Two keys held simultaneously → both axes advance independently.
func test_pan_wasd_diagonal_both_axes_advance() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera._held_directions[&"move_right"] = true
	_camera._held_directions[&"move_down"] = true
	_camera._process(0.01667)
	assert_float(_camera.position.x).is_between(8.524, 8.544)
	assert_float(_camera.position.y).is_between(8.524, 8.544)


## delta = 0.0 → no movement.
func test_pan_wasd_zero_delta_no_movement() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera._held_directions[&"move_right"] = true
	_camera._process(0.0)
	assert_float(_camera.position.x).is_equal(0.0)


## pan_speed = 0 → no movement regardless of held key.
func test_pan_wasd_zero_speed_no_movement() -> void:
	_camera.pan_speed_tiles_per_second = 0.0
	_camera._held_directions[&"move_right"] = true
	_camera._process(0.01667)
	assert_float(_camera.position.x).is_equal(0.0)


## No keys held → camera stays at origin.
func test_pan_wasd_no_keys_held_no_movement() -> void:
	_camera._process(0.01667)
	assert_vector(_camera.position).is_equal(Vector2.ZERO)


## Left key held → x decreases by ~8.534 px.
func test_pan_wasd_left_key_negative_x() -> void:
	_camera.position = Vector2(100.0, 0.0)
	_camera.pan_speed_tiles_per_second = 8.0
	_camera._held_directions[&"move_left"] = true
	_camera._process(0.01667)
	assert_float(_camera.position.x).is_between(91.456, 91.476)


## Up key held one frame → y decreases by ~8.534 px.
func test_pan_wasd_up_key_negative_y() -> void:
	_camera.position = Vector2(0.0, 100.0)
	_camera.pan_speed_tiles_per_second = 8.0
	_camera._held_directions[&"move_up"] = true
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_between(91.456, 91.476)
	assert_float(_camera.position.x).is_equal(0.0)


## Down key held one frame → y increases by ~8.534 px.
func test_pan_wasd_down_key_positive_y() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera._held_directions[&"move_down"] = true
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_between(8.524, 8.544)
	assert_float(_camera.position.x).is_equal(0.0)


# --- AC-6: Edge scroll displacement ---

## Mouse in bottom edge zone → downward displacement ~2.134 px.
func test_edge_scroll_bottom_zone_displacement() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera.edge_zone_width = 20
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1065.0)
	_camera._ui_hovered_override = false
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_between(2.124, 2.144)


## Mouse at exact boundary (screen_height - edge_zone_width) → no scroll (exclusive).
func test_edge_scroll_boundary_exclusive_no_scroll() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera.edge_zone_width = 20
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1060.0)  # exactly 1080 - 20
	_camera._ui_hovered_override = false
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_equal(0.0)


## Mouse over UI control → edge scroll suppressed.
func test_edge_scroll_ui_hovered_suppresses_scroll() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera.edge_zone_width = 20
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1065.0)
	_camera._ui_hovered_override = true
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_equal(0.0)


# --- AC-8: Mouse-leave stops edge scroll ---

## NOTIFICATION_WM_MOUSE_EXIT clears _mouse_inside_window → next _process produces zero scroll.
func test_mouse_leave_stops_edge_scroll() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera.edge_zone_width = 20
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1065.0)
	_camera._ui_hovered_override = false
	_camera._mouse_inside_window = false  # simulate WM_MOUSE_EXIT
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_equal(0.0)


## Mouse re-enters window near edge → edge scroll resumes on next _process().
func test_mouse_reenter_near_edge_resumes_scroll() -> void:
	_camera.pan_speed_tiles_per_second = 8.0
	_camera.edge_zone_width = 20
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1065.0)
	_camera._ui_hovered_override = false
	_camera._mouse_inside_window = false
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_equal(0.0)
	_camera._mouse_inside_window = true  # simulate WM_MOUSE_ENTER
	var y_before: float = _camera.position.y
	_camera._process(0.01667)
	var y_delta: float = _camera.position.y - y_before
	assert_float(y_delta).is_between(2.124, 2.144)


## Edge scroll is suppressed when context is not WORLD_ACTIVE.
func test_edge_scroll_blocked_in_ui_active_context() -> void:
	_mock_ctx._current = _UI_ACTIVE
	_camera.pan_speed_tiles_per_second = 8.0
	_camera.edge_zone_width = 20
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1065.0)
	_camera._ui_hovered_override = false
	_camera._process(0.01667)
	assert_float(_camera.position.y).is_equal(0.0)


## Context not WORLD_ACTIVE → pan and edge scroll both disabled.
func test_pan_blocked_in_ui_active_context() -> void:
	_mock_ctx._current = _UI_ACTIVE
	_camera._held_directions[&"move_right"] = true
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._mouse_pos_override = Vector2(960.0, 1065.0)
	_camera._ui_hovered_override = false
	_camera._process(0.01667)
	assert_vector(_camera.position).is_equal(Vector2.ZERO)
