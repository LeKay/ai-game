## gdUnit4 test suite for Story 004: Coordinate Conversion.
##
## All assertions use TILE_SIZE = 64 (the implemented value in world_grid.gd).
## The ADR specifies 48; Story 001 implemented 64 — ACs adapted accordingly.
##
## AC-12: tile_to_world exact pixel center (adapted: 64px tiles)
## AC-13: world_to_tile floor conversion (adapted: 64px tiles)
## AC-14: Mouse-to-tile with camera identity (no offset, zoom=1.0)

extends GdUnitTestSuite


func _make_grid() -> WorldGrid:
	var grid := WorldGrid.new()
	add_child(grid)
	auto_free(grid)
	return grid


# ---- AC-12: tile_to_world returns pixel center ----

func test_tile_to_world_returns_center_of_tile_5_12() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var result: Vector2 = grid.tile_to_world(Vector2i(5, 12))

	# Assert — 5*64+32=352, 12*64+32=800
	assert_vector(result).is_equal(Vector2(352.0, 800.0))


func test_tile_to_world_origin_tile_returns_half_tile_offset() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var result: Vector2 = grid.tile_to_world(Vector2i(0, 0))

	# Assert — center of tile (0,0) is at (32, 32)
	assert_vector(result).is_equal(Vector2(32.0, 32.0))


func test_tile_to_world_far_corner_tile_29_29() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var result: Vector2 = grid.tile_to_world(Vector2i(29, 29))

	# Assert — 29*64+32=1888
	assert_vector(result).is_equal(Vector2(1888.0, 1888.0))


# ---- AC-13: world_to_tile uses floor division ----

func test_world_to_tile_pixel_400_300_returns_tile_6_4() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var result: Vector2i = grid.world_to_tile(Vector2(400.0, 300.0))

	# Assert — floori(400/64)=6, floori(300/64)=4
	assert_that(result).is_equal(Vector2i(6, 4))


func test_world_to_tile_origin_returns_zero_zero() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var result: Vector2i = grid.world_to_tile(Vector2(0.0, 0.0))

	# Assert
	assert_that(result).is_equal(Vector2i(0, 0))


func test_world_to_tile_pixel_just_before_boundary_stays_in_tile_0() -> void:
	# Arrange
	var grid := _make_grid()

	# Act — 63.9 is still within tile 0 (tiles span 0..63)
	var result: Vector2i = grid.world_to_tile(Vector2(63.9, 63.9))

	# Assert
	assert_that(result).is_equal(Vector2i(0, 0))


func test_world_to_tile_pixel_at_boundary_enters_tile_1() -> void:
	# Arrange
	var grid := _make_grid()

	# Act — pixel 64 is the first pixel of tile 1
	var result: Vector2i = grid.world_to_tile(Vector2(64.0, 64.0))

	# Assert
	assert_that(result).is_equal(Vector2i(1, 1))


# ---- AC-14: Camera identity pass-through ----

func test_world_to_tile_with_camera_identity_matches_direct_conversion() -> void:
	# Arrange
	var grid := _make_grid()
	var screen_pos := Vector2(400.0, 300.0)
	var camera_offset := Vector2(0.0, 0.0)
	var camera_zoom := 1.0

	# Act — simulate consuming system formula: world_pos = offset + screen / zoom
	var world_pos: Vector2 = camera_offset + screen_pos / camera_zoom
	var result: Vector2i = grid.world_to_tile(world_pos)

	# Assert
	assert_that(result).is_equal(Vector2i(6, 4))


func test_world_to_tile_with_camera_zoom_2x_halves_world_coords() -> void:
	# Arrange
	var grid := _make_grid()
	var screen_pos := Vector2(400.0, 300.0)
	var camera_offset := Vector2(0.0, 0.0)
	var camera_zoom := 2.0

	# Act — zoom=2: world_pos = (200, 150); floori(200/64)=3, floori(150/64)=2
	var world_pos: Vector2 = camera_offset + screen_pos / camera_zoom
	var result: Vector2i = grid.world_to_tile(world_pos)

	# Assert
	assert_that(result).is_equal(Vector2i(3, 2))


# ---- Round-trip consistency ----

func test_round_trip_origin_tile() -> void:
	# Arrange
	var grid := _make_grid()
	var original := Vector2i(0, 0)

	# Act
	var result: Vector2i = grid.world_to_tile(grid.tile_to_world(original))

	# Assert
	assert_that(result).is_equal(original)


func test_round_trip_center_tile() -> void:
	# Arrange
	var grid := _make_grid()
	var original := Vector2i(15, 15)

	# Act
	var result: Vector2i = grid.world_to_tile(grid.tile_to_world(original))

	# Assert
	assert_that(result).is_equal(original)


func test_round_trip_far_corner_tile() -> void:
	# Arrange
	var grid := _make_grid()
	var original := Vector2i(29, 29)

	# Act
	var result: Vector2i = grid.world_to_tile(grid.tile_to_world(original))

	# Assert
	assert_that(result).is_equal(original)
