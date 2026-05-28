extends GdUnitTestSuite

## Tests for CameraController coordinate conversion (Story 004 — Coordinate Conversion).
## Covers AC-1 (screen_to_tile known value), AC-2 (tile_to_screen known value),
## AC-11 (OOB clamping), and roundtrip consistency.
##
## TILE_SIZE=64, GRID_SIZE=30. Tile centre offset = 32px.

var _camera: CameraController


func before_test() -> void:
	_camera = CameraController.new()
	add_child(_camera)


func after_test() -> void:
	_camera.queue_free()
	_camera = null


# --- AC-1: screen_to_tile known value ---

## AC-1 main: offset (0,0), zoom 1.0, screen pos (320,640) → tile (5,10).
## world_pos = (320,640); floor(320/64, 640/64) = floor(5.0, 10.0) = (5,10).
func test_coordinate_conversion_screen_to_tile_known_value_ac1() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(320.0, 640.0))
	assert_that(result).is_equal(Vector2i(5, 10))


## AC-1 edge: screen origin (0,0) maps to tile (0,0).
func test_coordinate_conversion_screen_to_tile_origin_returns_zero_tile() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(0.0, 0.0))
	assert_that(result).is_equal(Vector2i(0, 0))


## AC-1 edge: screen pos (1919,1919) at zoom 1.0, offset (0,0) → tile (29,29).
## floor(1919/64) = floor(29.984) = 29; within bounds — no clamp needed.
func test_coordinate_conversion_screen_to_tile_last_tile_at_edge() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(1919.0, 1919.0))
	assert_that(result).is_equal(Vector2i(29, 29))


# --- AC-2: tile_to_screen known value ---

## AC-2 main: offset (0,0), zoom 1.0, tile (5,10) → screen (352.0, 672.0).
## world_pos = (5*64+32, 10*64+32) = (352,672); screen = (352-0)*1.0 = (352,672).
func test_coordinate_conversion_tile_to_screen_known_value_ac2() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2 = _camera.tile_to_screen(Vector2i(5, 10))
	assert_float(result.x).is_between(351.9, 352.1)
	assert_float(result.y).is_between(671.9, 672.1)


## AC-2 edge: tile (0,0) → tile centre at screen (32.0, 32.0).
## world_pos = (0*64+32, 0*64+32) = (32,32); screen = (32-0)*1.0 = (32,32).
func test_coordinate_conversion_tile_to_screen_origin_tile_returns_centre() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2 = _camera.tile_to_screen(Vector2i(0, 0))
	assert_float(result.x).is_between(31.9, 32.1)
	assert_float(result.y).is_between(31.9, 32.1)


# --- AC-11: OOB screen position clamped to nearest edge tile ---

## AC-11 main: screen (2000,500), offset (0,0), zoom 1.0 → tile (29,7).
## 2000/64=31.25 → floor=31, clamped to 29; 500/64=7.8 → floor=7, within bounds.
func test_coordinate_conversion_screen_to_tile_oob_x_clamped_to_right_edge_ac11() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(2000.0, 500.0))
	assert_that(result).is_equal(Vector2i(29, 7))


## AC-11 edge: negative screen position clamped to (0,0).
func test_coordinate_conversion_screen_to_tile_negative_position_clamped_to_origin() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(-100.0, -200.0))
	assert_that(result).is_equal(Vector2i(0, 0))


## AC-11 edge: both axes OOB → clamped to corner tile (29,29).
func test_coordinate_conversion_screen_to_tile_both_axes_oob_clamped_to_corner() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(9999.0, 9999.0))
	assert_that(result).is_equal(Vector2i(29, 29))


# --- Roundtrip consistency ---

## Roundtrip: screen_to_tile(tile_to_screen(t)) == t for all valid tile coords.
## Tests corners and centre tile.
func test_coordinate_conversion_roundtrip_tile_to_screen_to_tile_is_identity() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(1.0, 1.0)
	for tile in [Vector2i(0, 0), Vector2i(29, 29), Vector2i(0, 29), Vector2i(29, 0), Vector2i(15, 15)]:
		var screen_pos: Vector2 = _camera.tile_to_screen(tile)
		var back: Vector2i = _camera.screen_to_tile(screen_pos)
		assert_that(back).is_equal(tile)


## Non-zero camera offset shifts which tile a screen pos maps to.
## offset=(64,128), zoom=1.0, screen (24,24) → world (88,152) → tile (1,2).
func test_coordinate_conversion_screen_to_tile_with_nonzero_camera_offset() -> void:
	_camera.position = Vector2(64.0, 128.0)
	_camera.zoom = Vector2(1.0, 1.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(24.0, 24.0))
	assert_that(result).is_equal(Vector2i(1, 2))


## Zoom > 1 compresses screen space: zoom=2.0, screen (128,128) → world (0+64, 0+64) = (64,64) → tile (1,1).
func test_coordinate_conversion_screen_to_tile_with_zoom_above_one() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(2.0, 2.0)
	var result: Vector2i = _camera.screen_to_tile(Vector2(128.0, 128.0))
	assert_that(result).is_equal(Vector2i(1, 1))


## Roundtrip at zoom=2.0: screen_to_tile(tile_to_screen(t)) == t holds at non-unit zoom.
## tile (5,10): tile_to_screen → screen; screen_to_tile → (5,10).
func test_coordinate_conversion_roundtrip_zoom_above_one_is_identity() -> void:
	_camera.position = Vector2(0.0, 0.0)
	_camera.zoom = Vector2(2.0, 2.0)
	for tile in [Vector2i(0, 0), Vector2i(5, 10), Vector2i(29, 29)]:
		var screen_pos: Vector2 = _camera.tile_to_screen(tile)
		var back: Vector2i = _camera.screen_to_tile(screen_pos)
		assert_that(back).is_equal(tile)
