extends GdUnitTestSuite

## Tests for CameraController zoom input (Story 002 — Zoom with Mouse Anchor).
## Covers AC-3 (zoom clamping) and AC-7 (zoom anchor formula).
##
## MIN_ZOOM=1.0 (fill-width is the floor — cannot zoom out past map width).
## MAX_ZOOM=2.0. Zoom-in = scroll up, zoom-out = scroll down.

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
	add_child(_mock_ctx)
	add_child(_camera)


func after_test() -> void:
	_camera.queue_free()
	_mock_ctx.queue_free()
	_camera = null
	_mock_ctx = null


func _scroll_up(factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.factor = factor
	_camera._unhandled_input(event)


func _scroll_down(factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.factor = factor
	_camera._unhandled_input(event)


# --- AC-3: Zoom clamping ---

## Scroll up factor 3.0 from zoom 1.0 → clamped to MAX_ZOOM 2.0.
func test_zoom_scroll_up_clamped_at_max() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 1.0
	_scroll_up(3.0)
	assert_float(_camera.zoom.x).is_between(1.999, 2.001)


## Scroll down factor 2.0 from zoom 1.0 → clamped to MIN_ZOOM 1.0 (already at min).
func test_zoom_scroll_down_clamped_at_min() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 1.0
	_scroll_down(2.0)
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)


## Scroll up when already at MAX_ZOOM → zoom stays at 2.0.
func test_zoom_stays_at_max_when_already_max() -> void:
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.zoom_sensitivity = 1.0
	_scroll_up(1.0)
	assert_float(_camera.zoom.x).is_between(1.999, 2.001)


## Scroll down when already at MIN_ZOOM 1.0 → zoom stays at 1.0.
func test_zoom_stays_at_min_when_already_min() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 1.0
	_scroll_down(1.0)
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)


## Scroll up factor 0.1 from zoom 1.0 → zoom increases without clamping.
func test_zoom_scroll_up_small_delta_no_clamp() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 1.0
	_scroll_up(0.1)
	assert_float(_camera.zoom.x).is_between(1.099, 1.101)


## Sensitivity 0.5 with factor 1.0 → zoom increases by 0.5 only.
func test_zoom_sensitivity_scales_delta() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 0.5
	_scroll_up(1.0)
	assert_float(_camera.zoom.x).is_between(1.499, 1.501)


# --- AC-7: Zoom anchor formula ---

## Camera at (200,150), zoom 1.0, mouse (400,300), scroll +2.0 → new zoom 2.0, offset (400,300).
## Derivation: world_before=(400/1+200, 300/1+150)=(600,450);
##   new_offset=(600,450)-(400/2,300/2)=(400,300).
func test_zoom_anchor_mouse_offset_matches_spec() -> void:
	_camera.position = Vector2(200.0, 150.0)
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 1.0
	_camera._mouse_pos_override = Vector2(400.0, 300.0)
	_scroll_up(2.0)
	assert_float(_camera.zoom.x).is_between(1.999, 2.001)
	assert_float(_camera.position.x).is_between(399.99, 400.01)
	assert_float(_camera.position.y).is_between(299.99, 300.01)


## Mouse at (0,0) → anchor at world origin, camera position unchanged on zoom-in.
## Derivation: world_before=(0+100, 0+100)=(100,100); new_offset=(100,100)-(0,0)=(100,100).
func test_zoom_anchor_mouse_at_origin_offset_unchanged() -> void:
	_camera.position = Vector2(100.0, 100.0)
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.zoom_sensitivity = 1.0
	_camera._mouse_pos_override = Vector2(0.0, 0.0)
	_scroll_up(1.0)
	assert_float(_camera.position.x).is_between(99.99, 100.01)
	assert_float(_camera.position.y).is_between(99.99, 100.01)


## Zoom out from 2.0 to 1.0, mouse (400,300), camera at (400,300) → new offset (200,150).
## Derivation: world_before=(400/2+400, 300/2+300)=(600,450);
##   new_zoom=1.0, new_offset=(600,450)-(400/1,300/1)=(200,150).
func test_zoom_anchor_zoom_out_adjusts_offset() -> void:
	_camera.position = Vector2(400.0, 300.0)
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.zoom_sensitivity = 1.0
	_camera._mouse_pos_override = Vector2(400.0, 300.0)
	_scroll_down(1.0)
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)
	assert_float(_camera.position.x).is_between(199.99, 200.01)
	assert_float(_camera.position.y).is_between(149.99, 150.01)


# --- Context gating ---

## Scroll wheel ignored when context is not WORLD_ACTIVE.
func test_zoom_blocked_outside_world_active_context() -> void:
	_mock_ctx._current = _UI_ACTIVE
	_camera.zoom = Vector2(1.0, 1.0)
	_scroll_up(3.0)
	assert_float(_camera.zoom.x).is_between(0.999, 1.001)
