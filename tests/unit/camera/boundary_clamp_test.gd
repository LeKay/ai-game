extends GdUnitTestSuite

## Tests for CameraController boundary clamping (Story 003 — Boundary Clamping).
## Covers AC-4 (right-boundary clamp), AC-9 (resize re-clamp),
## AC-10 (view-exceeds-map lock), and AC-12 (no visible jump on resize).
##
## TILE_SIZE=64, GRID_SIZE=30 → max_world=1920px.

var _camera: CameraController

## MAX_X = MAX_Y = GRID_SIZE(30) * TILE_SIZE(64) = 1920
const _MAX_WORLD: float = 1920.0


func before_test() -> void:
	_camera = CameraController.new()
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	add_child(_camera)


func after_test() -> void:
	_camera.queue_free()
	_camera = null


# --- AC-4: Right-boundary clamp at zoom 1.5 ---

## AC-4 main: offset (800,300), zoom 1.5, screen 1920×1080.
## view_width=1280, clamp_x=clamp(800,0,640)=640. view_height=720, clamp_y=300 (unchanged).
func test_boundary_clamp_right_boundary_zoom_1_5() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(800.0, 300.0)
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(639.9, 640.1)
	assert_float(_camera.position.y).is_between(299.9, 300.1)


## AC-4 edge: offset (0,0) at zoom 1.5 is within bounds — no clamp needed.
func test_boundary_clamp_no_clamp_when_within_bounds() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(0.0, 0.0)
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(-0.01, 0.01)
	assert_float(_camera.position.y).is_between(-0.01, 0.01)


## AC-4 edge: negative offset clamped to 0 (should not arise in practice).
func test_boundary_clamp_negative_offset_clamped_to_zero() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(-10.0, -5.0)
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(-0.01, 0.01)
	assert_float(_camera.position.y).is_between(-0.01, 0.01)


# --- AC-9: Window resize re-clamp ---

## AC-9 main: after resize to 1280×720 at zoom 1.0, view_width=1280 < 1920 → clamp x∈[0,640].
## Offset (0,0) stays valid; verifies formula uses new screen dimensions.
func test_boundary_clamp_resize_updates_view_dimensions() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(0.0, 0.0)
	# Simulate resize: change override, trigger handler
	_camera._screen_size_override = Vector2(1280.0, 720.0)
	_camera._on_viewport_size_changed()
	# view_width=1280 < 1920, so clamp x ∈ [0,640]; offset 0 is valid
	assert_float(_camera.position.x).is_between(-0.01, 0.01)
	assert_float(_camera.position.y).is_between(-0.01, 0.01)


## AC-9 edge: resize to viewport wider than world locks x to origin.
## zoom=1.0, resize to 1920×1080 → view_width=1920 = max_world → x locked at 0.
## view_height=1080 < 1920 → y∈[0,840]; position.y=50 stays valid.
func test_boundary_clamp_resize_to_large_viewport_locks_to_origin() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(50.0, 50.0)
	_camera._screen_size_override = Vector2(1920.0, 1080.0)
	_camera._on_viewport_size_changed()
	assert_float(_camera.position.x).is_between(-0.01, 0.01)
	# y=50 is within [0, 1920-1080=840] → unchanged
	assert_float(_camera.position.y).is_between(49.9, 50.1)


# --- AC-10: View-exceeds-map locks camera at 0 ---

## AC-10 main: zoom=1.0, screen 1920×1080 → view_width=1920 = max_world → locked at 0.
## (MIN_ZOOM=1.0 means this is the normal minimum zoom state.)
func test_boundary_clamp_view_exceeds_map_width_locked_at_zero() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(100.0, 0.0)
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(-0.01, 0.01)


## AC-10 edge: view_width exactly equals MAX_X → locked at 0 (boundary is inclusive).
## zoom = 1920/1920 = 1.0, view_width = 1920.0 exactly.
func test_boundary_clamp_view_equals_map_width_locked_at_zero() -> void:
	var exact_zoom: float = 1920.0 / _MAX_WORLD  # 1.0
	_camera.zoom = Vector2(exact_zoom, exact_zoom)
	_camera.position = Vector2(50.0, 0.0)
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(-0.01, 0.01)


## AC-10 pan suppression: zoom=1.0 locks x at 0; simulated pan displacement is undone by clamp.
func test_boundary_clamp_pan_right_suppressed_when_view_exceeds_map() -> void:
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(0.0, 0.0)
	# Simulate pan moving camera right (as if _apply_key_pan ran)
	_camera.position.x = 30.0
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(-0.01, 0.01)


# --- AC-12: No visible jump on resize ---

## AC-12 main: valid offset preserved after resize — no jump.
## zoom=1.5, offset=(50,100), resize 1920×1080→1280×720.
## New bounds: view_width=853, x∈[0,1067]; view_height=480, y∈[0,1440] — offset still valid.
func test_boundary_clamp_valid_offset_preserved_after_resize() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(50.0, 100.0)
	_camera._screen_size_override = Vector2(1280.0, 720.0)
	_camera._on_viewport_size_changed()
	assert_float(_camera.position.x).is_between(49.9, 50.1)
	assert_float(_camera.position.y).is_between(99.9, 100.1)


## AC-12 edge: offset that exceeds original bounds is minimally clamped, not reset to 0.
## zoom=1.5, offset=(800,0), 1920×1080 → clamped to 640.
## Resize to 1280×720 → new bound = [0,1067] → 640 stays valid (no change).
func test_boundary_clamp_out_of_bounds_offset_minimally_corrected_not_reset() -> void:
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position = Vector2(800.0, 0.0)
	# First clamp at 1920×1080 → x=640
	_camera._apply_boundary_clamp()
	assert_float(_camera.position.x).is_between(639.9, 640.1)
	# Resize to 1280×720 → bound=[0,1067], 640 is valid — position stays 640
	_camera._screen_size_override = Vector2(1280.0, 720.0)
	_camera._on_viewport_size_changed()
	assert_float(_camera.position.x).is_between(639.9, 640.1)
