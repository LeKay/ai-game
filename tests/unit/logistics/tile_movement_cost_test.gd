extends GdUnitTestSuite
## Tests for WorldGrid tile movement cost data model — Story 009 (TR-logistics-015).
## Covers AC-1 through AC-8: cost resolution, is_tile_passable, and terrain_changed signal.

const BUILDING_ID := "test_building_001"
const RESOURCE_ID_WOOD := &"wood"

var _grid: WorldGrid


func before_test() -> void:
	_grid = WorldGrid.new()
	add_child(_grid)


func after_test() -> void:
	_grid.queue_free()
	_grid = null


# --- AC-1: Open tile returns 1.0 ---

func test_open_tile_returns_base_cost() -> void:
	var cost: float = _grid.get_tile_movement_cost(Vector2i(5, 5))
	assert_float(cost).is_equal(1.0)


func test_out_of_bounds_returns_inf() -> void:
	var cost: float = _grid.get_tile_movement_cost(Vector2i(-1, 0))
	assert_bool(cost == INF).is_true()


func test_out_of_bounds_high_returns_inf() -> void:
	var cost: float = _grid.get_tile_movement_cost(Vector2i(30, 30))
	assert_bool(cost == INF).is_true()


# --- AC-2: Resource tile returns its movement_cost ---

func test_resource_tile_returns_movement_cost() -> void:
	_grid.add_resource_to_tile(Vector2i(3, 3), RESOURCE_ID_WOOD)
	var cost: float = _grid.get_tile_movement_cost(Vector2i(3, 3))
	assert_float(cost).is_equal(4.0)


# --- AC-3: Building tile returns INF ---

func test_building_tile_returns_inf() -> void:
	_grid.place_building(Vector2i(7, 2), BUILDING_ID)
	var cost: float = _grid.get_tile_movement_cost(Vector2i(7, 2))
	assert_bool(cost == INF).is_true()


# --- AC-4: Building overrides resource (building takes priority) ---

func test_building_overrides_resource_layer() -> void:
	# Place resource first, then building (place_building clears resources)
	_grid.add_resource_to_tile(Vector2i(4, 4), RESOURCE_ID_WOOD)
	_grid.place_building(Vector2i(4, 4), BUILDING_ID)
	var cost: float = _grid.get_tile_movement_cost(Vector2i(4, 4))
	assert_bool(cost == INF).is_true()


# --- AC-5: is_tile_passable consistency ---

func test_is_tile_passable_open_tile_is_true() -> void:
	assert_bool(_grid.is_tile_passable(Vector2i(2, 2))).is_true()


func test_is_tile_passable_resource_tile_is_true() -> void:
	_grid.add_resource_to_tile(Vector2i(1, 1), RESOURCE_ID_WOOD)
	assert_bool(_grid.is_tile_passable(Vector2i(1, 1))).is_true()


func test_is_tile_passable_building_tile_is_false() -> void:
	_grid.place_building(Vector2i(6, 6), BUILDING_ID)
	assert_bool(_grid.is_tile_passable(Vector2i(6, 6))).is_false()


func test_is_tile_passable_out_of_bounds_is_false() -> void:
	assert_bool(_grid.is_tile_passable(Vector2i(-5, 0))).is_false()


# --- AC-6: terrain_changed emitted on building placement ---

func test_terrain_changed_emitted_on_place_building() -> void:
	var monitor := monitor_signals(_grid)
	_grid.place_building(Vector2i(2, 2), BUILDING_ID)
	assert_signal(monitor).is_emitted("terrain_changed") \
		.with_args([Vector2i(2, 2), WorldGrid.BUILDING_LAYER])


# --- AC-7: terrain_changed emitted on building demolition ---

func test_terrain_changed_emitted_on_remove_building() -> void:
	_grid.place_building(Vector2i(2, 2), BUILDING_ID)
	var monitor := monitor_signals(_grid)
	_grid.remove_building(Vector2i(2, 2))
	assert_signal(monitor).is_emitted("terrain_changed") \
		.with_args([Vector2i(2, 2), WorldGrid.BUILDING_LAYER])


# --- AC-8: terrain_changed emitted on resource removal ---

func test_terrain_changed_emitted_on_remove_resource() -> void:
	_grid.add_resource_to_tile(Vector2i(6, 6), RESOURCE_ID_WOOD)
	var monitor := monitor_signals(_grid)
	_grid.remove_one_resource(Vector2i(6, 6), 0)
	assert_signal(monitor).is_emitted("terrain_changed") \
		.with_args([Vector2i(6, 6), WorldGrid.RESOURCE_LAYER])


func test_terrain_changed_emitted_on_add_resource() -> void:
	var monitor := monitor_signals(_grid)
	_grid.add_resource_to_tile(Vector2i(8, 8), RESOURCE_ID_WOOD)
	assert_signal(monitor).is_emitted("terrain_changed") \
		.with_args([Vector2i(8, 8), WorldGrid.RESOURCE_LAYER])
