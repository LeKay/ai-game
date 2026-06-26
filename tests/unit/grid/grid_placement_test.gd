## GdUnit4 test suite for Story grid-003: Building Placement Validation Gate.
##
## Covers validate_placement, place_building, and remove_building stubs
## implemented in world_grid.gd.

extends GdUnitTestSuite

const WorldGridScript := preload("res://src/systems/world_grid.gd")


func _make_grid() -> WorldGridScript:
	var grid := WorldGridScript.new()
	# _init_arrays() is called by _ready(); invoke it directly so we don't need the scene tree.
	grid._init_arrays()
	auto_free(grid)
	return grid


# ---- validate_placement ----

func test_validate_placement_empty_tile_returns_success() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(5, 5)
	# tile is EMPTY, no building, no resources by default

	# Act
	var result: int = grid.validate_placement(tile, 0)

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.SUCCESS)


func test_validate_placement_impassable_returns_blocked() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(3, 3)
	grid._terrain[tile.x][tile.y] = WorldGridScript.TileType.IMPASSABLE

	# Act
	var result: int = grid.validate_placement(tile, 0)

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.BLOCKED_BY_IMPASSABLE)


func test_validate_placement_occupied_returns_blocked_by_building() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(7, 7)
	grid._buildings[tile.x][tile.y] = "existing_building"

	# Act
	var result: int = grid.validate_placement(tile, 0)

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.BLOCKED_BY_BUILDING)


func test_validate_placement_out_of_bounds_returns_blocked_by_bounds() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(-1, 0)

	# Act
	var result: int = grid.validate_placement(tile, 0)

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.BLOCKED_BY_BOUNDS)


func test_validate_placement_nonclearable_resource_returns_blocked() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(10, 10)
	var res := WorldGridScript.ResourceTileData.new(&"stone", false)
	grid._resources[tile.x][tile.y] = [res]

	# Act
	var result: int = grid.validate_placement(tile, 0)

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.BLOCKED_BY_RESOURCE_TILE)


func test_validate_placement_clearable_resource_returns_success() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(10, 10)
	var res := WorldGridScript.ResourceTileData.new(&"wood", true)
	grid._resources[tile.x][tile.y] = [res]

	# Act
	var result: int = grid.validate_placement(tile, 0)

	# Assert — clearable resources do not block placement
	assert_int(result).is_equal(WorldGridScript.PlacementResult.SUCCESS)


# ---- place_building ----

func test_place_building_updates_building_layer() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(2, 2)

	# Act
	var result: int = grid.place_building(tile, "building_0")

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.SUCCESS)
	assert_str(grid._buildings[tile.x][tile.y]).is_equal("building_0")


func test_place_building_clears_clearable_resource() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(4, 4)
	var res := WorldGridScript.ResourceTileData.new(&"wood", true)
	grid._resources[tile.x][tile.y] = [res]

	# Act
	grid.place_building(tile, "building_1")

	# Assert — clearable resource array is wiped
	assert_int(grid._resources[tile.x][tile.y].size()).is_equal(0)


func test_place_building_blocked_by_impassable() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(6, 6)
	grid._terrain[tile.x][tile.y] = WorldGridScript.TileType.IMPASSABLE

	# Act
	var result: int = grid.place_building(tile, "building_2")

	# Assert
	assert_int(result).is_equal(WorldGridScript.PlacementResult.BLOCKED_BY_IMPASSABLE)
	# Building layer must remain null (no partial write)
	assert_bool(grid._buildings[tile.x][tile.y] == null).is_true()


# ---- remove_building ----

func test_remove_building_returns_true_when_building_present() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(8, 8)
	grid._buildings[tile.x][tile.y] = "building_3"

	# Act
	var removed: bool = grid.remove_building(tile)

	# Assert
	assert_bool(removed).is_true()
	assert_bool(grid._buildings[tile.x][tile.y] == null).is_true()


func test_remove_building_returns_false_when_no_building() -> void:
	# Arrange
	var grid := _make_grid()
	var tile := Vector2i(9, 9)
	# tile has no building by default

	# Act
	var removed: bool = grid.remove_building(tile)

	# Assert
	assert_bool(removed).is_false()
