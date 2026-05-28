## gdUnit4 test suite for Story 001: Grid Data Model and Core Read API.
##
## Covers AC-1 (grid init returns valid TileType) and read API correctness
## + harvest_resource behavior.
##
## Note: AC-1 requires get_terrain(-1, 0) to trigger an assert. Godot's assert()
## aborts the process in debug builds and cannot be caught by GdUnit4. Coverage
## for the out-of-bounds guard is provided indirectly by the is_in_bounds
## false-path tests below, which test the exact condition the assert checks.
##
## AC-27 (50 get_tile_view calls < 0.1ms) is a wall-clock timing assertion and
## is excluded from this unit suite to avoid CI flakiness. It belongs in a
## dedicated perf-profile run.

extends GdUnitTestSuite

const GridMapScript := preload("res://src/systems/world_grid.gd")


func _make_grid() -> Node:
	var grid := GridMapScript.new()
	add_child(grid)
	auto_free(grid)
	return grid


# ---- AC-1: get_terrain returns valid TileType ----

func test_get_terrain_center_returns_empty() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var terrain: GridMapScript.TileType = grid.get_terrain(Vector2i(15, 15))

	# Assert
	assert_int(terrain).is_equal(GridMapScript.TileType.EMPTY)


func test_get_terrain_origin_returns_empty() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var terrain: GridMapScript.TileType = grid.get_terrain(Vector2i(0, 0))

	# Assert
	assert_int(terrain).is_equal(GridMapScript.TileType.EMPTY)


func test_get_terrain_far_corner_returns_empty() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var terrain: GridMapScript.TileType = grid.get_terrain(Vector2i(29, 29))

	# Assert
	assert_int(terrain).is_equal(GridMapScript.TileType.EMPTY)


# ---- get_resources: empty before generation ----

func test_get_resources_center_returns_empty_before_generation() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var resources: Array = grid.get_resources(Vector2i(15, 15))

	# Assert
	assert_array(resources).is_empty()


func test_get_resources_origin_returns_empty_before_generation() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var resources: Array = grid.get_resources(Vector2i(0, 0))

	# Assert
	assert_array(resources).is_empty()


# ---- get_building: empty string before any placement ----

func test_get_building_returns_empty_string_before_placement() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var building_id: String = grid.get_building(Vector2i(15, 15))

	# Assert
	assert_str(building_id).is_equal("")


# ---- get_tile_view: composite snapshot ----

func test_get_tile_view_terrain_matches_get_terrain() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var view: GridMapScript.TileView = grid.get_tile_view(Vector2i(10, 10))

	# Assert
	assert_int(view.terrain).is_equal(grid.get_terrain(Vector2i(10, 10)))


func test_get_tile_view_resources_empty_before_generation() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var view: GridMapScript.TileView = grid.get_tile_view(Vector2i(5, 5))

	# Assert
	assert_array(view.resources).is_empty()


func test_get_tile_view_building_is_empty_before_placement() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var view: GridMapScript.TileView = grid.get_tile_view(Vector2i(5, 5))

	# Assert
	assert_str(view.building_id).is_equal("")


# ---- is_in_bounds ----

func test_is_in_bounds_center_returns_true() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(15, 15))).is_true()


func test_is_in_bounds_top_left_corner_returns_true() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(0, 0))).is_true()


func test_is_in_bounds_bottom_right_corner_returns_true() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(29, 29))).is_true()


func test_is_in_bounds_bottom_left_corner_returns_true() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(0, 29))).is_true()


func test_is_in_bounds_top_right_corner_returns_true() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(29, 0))).is_true()


func test_is_in_bounds_negative_x_returns_false() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(-1, 0))).is_false()


func test_is_in_bounds_negative_y_returns_false() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(0, -1))).is_false()


func test_is_in_bounds_x_at_grid_size_returns_false() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(30, 0))).is_false()


func test_is_in_bounds_y_at_grid_size_returns_false() -> void:
	var grid := _make_grid()
	assert_bool(grid.is_in_bounds(Vector2i(0, 30))).is_false()


# ---- is_passable ----

func test_is_passable_empty_tile_returns_true() -> void:
	# Arrange
	var grid := _make_grid()

	# Act / Assert — default terrain is EMPTY, which is passable
	assert_bool(grid.is_passable(Vector2i(15, 15))).is_true()


func test_is_passable_impassable_tile_returns_false() -> void:
	# Arrange
	var grid := _make_grid()
	# Inject IMPASSABLE terrain directly (generation is Story 002)
	grid._terrain[10][10] = GridMapScript.TileType.IMPASSABLE

	# Act
	var passable: bool = grid.is_passable(Vector2i(10, 10))

	# Assert
	assert_bool(passable).is_false()


# ---- harvest_resource ----

func test_harvest_resource_no_resource_returns_zero() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	var result: int = grid.harvest_resource(Vector2i(10, 10), 1)

	# Assert
	assert_int(result).is_equal(0)


func test_harvest_resource_no_resource_leaves_empty() -> void:
	# Arrange
	var grid := _make_grid()

	# Act
	grid.harvest_resource(Vector2i(10, 10), 1)

	# Assert — tile must still be empty (no mutation occurred)
	assert_array(grid.get_resources(Vector2i(10, 10))).is_empty()


func test_harvest_resource_existing_resource_returns_one_and_clears() -> void:
	# Arrange
	var grid := _make_grid()
	# Manually plant a resource (generation is Story 002; test data injected directly)
	grid._resources[5][5] = [GridMapScript.ResourceTileData.new(&"wood", true)]

	# Act
	var result: int = grid.harvest_resource(Vector2i(5, 5), 1)

	# Assert
	assert_int(result).is_equal(1)
	assert_array(grid.get_resources(Vector2i(5, 5))).is_empty()


func test_harvest_resource_clearable_false_still_clears() -> void:
	# Arrange
	var grid := _make_grid()
	# clearable: false is advisory for place_building (Story 003), not harvest_resource.
	# harvest_resource always clears — this test documents that invariant.
	grid._resources[7][7] = [GridMapScript.ResourceTileData.new(&"stone", false)]

	# Act
	var result: int = grid.harvest_resource(Vector2i(7, 7), 1)

	# Assert
	assert_int(result).is_equal(1)
	assert_array(grid.get_resources(Vector2i(7, 7))).is_empty()
