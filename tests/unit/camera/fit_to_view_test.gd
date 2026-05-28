extends GdUnitTestSuite

## Tests for CameraController fit-to-view (Story 005 — Fit-to-View Reset).
## Covers AC-FV-1 (fit formula on 1920×1080), AC-FV-2 (R key in WORLD_ACTIVE),
## AC-FV-3 (blocked in UI_ACTIVE / PAUSED).
##
## TILE_SIZE=64, GRID_SIZE=30 → max_world=1920px.
## fit_to_view() sets zoom = screen.x / max_world, position = (0,0).

var _camera: CameraController
var _mock_ctx: _MockContext

const _WORLD_ACTIVE: int = 0
const _UI_ACTIVE: int = 1
const _PAUSED: int = 2


class _MockContext extends Node:
	var _current: int = 0

	func get_current() -> int:
		return _current


func before_test() -> void:
	_mock_ctx = _MockContext.new()
	_camera = CameraController.new()
	_camera._input_context = _mock_ctx
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	add_child(_mock_ctx)
	add_child(_camera)


func after_test() -> void:
	_camera.queue_free()
	_mock_ctx.queue_free()
	_camera = null
	_mock_ctx = null


func _fire_camera_reset(pressed: bool = true) -> void:
	var event := InputEventAction.new()
	event.action = InputActions.CAMERA_RESET
	event.pressed = pressed
	_camera._unhandled_input(event)


# --- AC-FV-1: fit_to_view formula on 1920×1080 screen ---

## AC-FV-1 zoom: ideal_zoom = 1920/1920 = 1.0 — fits exactly, no clamping.
func test_fit_to_view_1920x1080_zoom_fills_width() -> void:
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.position = Vector2(100.0, 50.0)
	_camera.fit_to_view()
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)


## AC-FV-1 x-offset: view_width=1920 = max_world → boundary clamp locks x to 0.
func test_fit_to_view_1920x1080_x_offset_locked_zero() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(200.0, 0.0)
	_camera.fit_to_view()
	assert_float(_camera.position.x).is_between(-0.5, 0.5)


## AC-FV-1 y-offset: position reset to (0,0) — camera starts at top of map.
func test_fit_to_view_1920x1080_y_offset_at_top() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(0.0, 500.0)
	_camera.fit_to_view()
	assert_float(_camera.position.y).is_between(-0.5, 0.5)


## AC-FV-1 idempotent: calling fit_to_view twice yields identical zoom and position.
func test_fit_to_view_1920x1080_idempotent() -> void:
	_camera.fit_to_view()
	var zoom_first: float = _camera.zoom.x
	var pos_first: Vector2 = _camera.position
	_camera.fit_to_view()
	assert_float(_camera.zoom.x).is_between(zoom_first - 0.001, zoom_first + 0.001)
	assert_float(_camera.position.y).is_between(pos_first.y - 0.5, pos_first.y + 0.5)


## AC-FV-1 edge: camera at MAX_ZOOM resets to fill-width zoom (1.0) after fit_to_view.
func test_fit_to_view_from_max_zoom_resets_to_fill_width() -> void:
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.position = Vector2(0.0, 0.0)
	_camera.fit_to_view()
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)


## AC-FV-1 small screen: 960×540 → ideal_zoom=960/1920=0.5 < MIN_ZOOM → clamped to 1.0.
func test_fit_to_view_960x540_zoom_clamped_to_min() -> void:
	_camera._screen_size_override = Vector2(960.0, 540.0)
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.fit_to_view()
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)


# --- AC-FV-2: camera_reset action in WORLD_ACTIVE triggers fit_to_view ---

## AC-FV-2 main: action pressed in WORLD_ACTIVE → zoom resets to fill-width (1.0).
func test_fit_to_view_camera_reset_in_world_active_triggers_fit() -> void:
	_mock_ctx._current = _WORLD_ACTIVE
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.position = Vector2(100.0, 100.0)
	_fire_camera_reset()
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)


## AC-FV-2 edge: action with pressed=false (key release) does not trigger fit_to_view.
func test_fit_to_view_camera_reset_key_release_does_not_trigger() -> void:
	_mock_ctx._current = _WORLD_ACTIVE
	_camera.zoom = Vector2(2.0, 2.0)
	_fire_camera_reset(false)
	assert_float(_camera.zoom.x).is_between(1.99, 2.01)


# --- AC-FV-3: camera_reset blocked outside WORLD_ACTIVE ---

## AC-FV-3 UI_ACTIVE: action fires but context gate blocks fit_to_view → zoom unchanged.
func test_fit_to_view_camera_reset_in_ui_active_blocked() -> void:
	_mock_ctx._current = _UI_ACTIVE
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(50.0, 50.0)
	_fire_camera_reset()
	assert_float(_camera.zoom.x).is_between(1.49, 1.51)
	assert_float(_camera.position.y).is_between(49.9, 50.1)


## AC-FV-3 PAUSED: action fires but context gate blocks fit_to_view → zoom unchanged.
func test_fit_to_view_camera_reset_in_paused_blocked() -> void:
	_mock_ctx._current = _PAUSED
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(50.0, 50.0)
	_fire_camera_reset()
	assert_float(_camera.zoom.x).is_between(1.49, 1.51)
	assert_float(_camera.position.y).is_between(49.9, 50.1)
