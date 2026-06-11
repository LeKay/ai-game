## GdUnit4 test suite for LogisticsPathfinder (Story 010 — Weighted A* Pathfinding).
## Covers AC-1 through AC-9 and all QA test cases TC-1 through TC-7.
##
## MockGrid provides a lightweight duck-typed grid substitute so that tests
## run without requiring WorldGrid (an instantiated Node) in the test scene.

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# MockGrid — mimics WorldGrid's two-method pathfinding interface.
# ---------------------------------------------------------------------------
class MockGrid:
	var width: int
	var height: int
	var costs: Dictionary  # Vector2i → float

	func _init(w: int, h: int, default_cost: float = 1.0) -> void:
		width = w
		height = h
		for x in range(w):
			for y in range(h):
				costs[Vector2i(x, y)] = default_cost

	func set_cost(pos: Vector2i, cost: float) -> void:
		costs[pos] = cost

	func set_impassable(pos: Vector2i) -> void:
		costs[pos] = INF

	func get_tile_movement_cost(pos: Vector2i) -> float:
		if pos.x < 0 or pos.y < 0 or pos.x >= width or pos.y >= height:
			return INF
		return costs.get(pos, 1.0)

	func is_tile_passable(pos: Vector2i) -> bool:
		return get_tile_movement_cost(pos) != INF


# ---------------------------------------------------------------------------
# AC-1 — PathResult has the correct fields with correct types/defaults
# ---------------------------------------------------------------------------

func test_path_result_found_defaults_false() -> void:
	# Arrange / Act
	var r := PathResult.new()
	# Assert
	assert_bool(r.found).is_equal(false)


func test_path_result_cost_defaults_zero() -> void:
	var r := PathResult.new()
	assert_float(r.cost).is_equal(0.0)


func test_path_result_path_defaults_empty() -> void:
	var r := PathResult.new()
	assert_int(r.path.size()).is_equal(0)


func test_path_result_failure_factory_found_false() -> void:
	var r := PathResult.failure()
	assert_bool(r.found).is_equal(false)


func test_path_result_failure_factory_cost_zero() -> void:
	var r := PathResult.failure()
	assert_float(r.cost).is_equal(0.0)


func test_path_result_failure_factory_path_empty() -> void:
	var r := PathResult.failure()
	assert_int(r.path.size()).is_equal(0)


func test_path_result_success_factory_found_true() -> void:
	var p: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var r := PathResult.success(p, 1.0)
	assert_bool(r.found).is_equal(true)


func test_path_result_success_factory_stores_cost() -> void:
	var p: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var r := PathResult.success(p, 3.5)
	assert_float(r.cost).is_equal(3.5)


func test_path_result_success_factory_stores_path() -> void:
	var p: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var r := PathResult.success(p, 1.0)
	assert_int(r.path.size()).is_equal(2)


# ---------------------------------------------------------------------------
# AC-2 — LogisticsPathfinder exposes find_path() as a static method
# ---------------------------------------------------------------------------

func test_logistics_pathfinder_find_path_returns_path_result() -> void:
	# Arrange
	var grid := MockGrid.new(3, 3)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(2, 2), grid)
	# Assert
	assert_object(result).is_not_null()
	assert_bool(result.found).is_true()


# ---------------------------------------------------------------------------
# TC-1 (AC-3, AC-9) — 5×5 flat grid, start(0,0)→goal(4,4)
# found=true, cost==8.0, path[0]==(0,0), path[-1]==(4,4)
# ---------------------------------------------------------------------------

func test_find_path_flat_5x5_finds_path() -> void:
	# Arrange
	var grid := MockGrid.new(5, 5, 1.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(4, 4), grid)
	# Assert
	assert_bool(result.found).is_true()


func test_find_path_flat_5x5_cost_equals_manhattan_distance() -> void:
	# Arrange — Manhattan distance (0,0)→(4,4) = 8 steps at cost 1.0 each
	var grid := MockGrid.new(5, 5, 1.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(4, 4), grid)
	# Assert
	assert_float(result.cost).is_equal_approx(8.0, 0.001)


func test_find_path_flat_5x5_path_starts_at_origin() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(4, 4), grid)
	assert_that(result.path[0]).is_equal(Vector2i(0, 0))


func test_find_path_flat_5x5_path_ends_at_goal() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(4, 4), grid)
	assert_that(result.path[result.path.size() - 1]).is_equal(Vector2i(4, 4))


# ---------------------------------------------------------------------------
# TC-2 (AC-5) — Wall at x=2 for all y, fully blocked
# found=false, path.size()==0, cost==0.0
# ---------------------------------------------------------------------------

func test_find_path_fully_blocked_wall_found_false() -> void:
	# Arrange — vertical wall at x=2 blocks all rows
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(5):
		grid.set_impassable(Vector2i(2, y))
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	# Assert
	assert_bool(result.found).is_false()


func test_find_path_fully_blocked_wall_path_empty() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(5):
		grid.set_impassable(Vector2i(2, y))
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	assert_int(result.path.size()).is_equal(0)


func test_find_path_fully_blocked_wall_cost_zero() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(5):
		grid.set_impassable(Vector2i(2, y))
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	assert_float(result.cost).is_equal(0.0)


# ---------------------------------------------------------------------------
# TC-3 (AC-6) — Wall with gap at (2,4), path must route through the gap
# ---------------------------------------------------------------------------

func test_find_path_wall_with_gap_found_true() -> void:
	# Arrange — wall at (2,0)..(2,3), gap at (2,4)
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(4):
		grid.set_impassable(Vector2i(2, y))
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	# Assert
	assert_bool(result.found).is_true()


func test_find_path_wall_with_gap_path_passes_through_gap() -> void:
	# Arrange
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(4):
		grid.set_impassable(Vector2i(2, y))
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	# Assert — the path must include the gap tile (2,4)
	assert_bool(result.path.has(Vector2i(2, 4))).is_true()


func test_find_path_wall_with_gap_path_starts_at_start() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(4):
		grid.set_impassable(Vector2i(2, y))
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	assert_that(result.path[0]).is_equal(Vector2i(0, 2))


func test_find_path_wall_with_gap_path_ends_at_goal() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	for y in range(4):
		grid.set_impassable(Vector2i(2, y))
	var result := LogisticsPathfinder.find_path(Vector2i(0, 2), Vector2i(4, 2), grid)
	assert_that(result.path[result.path.size() - 1]).is_equal(Vector2i(4, 2))


# ---------------------------------------------------------------------------
# TC-4 (AC-4) — Cost-optimal routing: detour (cost 6.0) beats direct (cost 7.0)
#
# Grid layout (5×3, all cost 1.0 except tile (2,1) which costs 4.0):
#   Row 0 (y=0): (0,0)(1,0)(2,0)(3,0)(4,0) — top row, cost 1.0 each
#   Row 1 (y=1): (0,1)(1,1)[4.0](3,1)(4,1) — middle row, centre tile expensive
#   Row 2 (y=2): (0,2)(1,2)(2,2)(3,2)(4,2) — bottom row, cost 1.0 each
#
# Direct  start(0,1)→(1,1)→(2,1)→(3,1)→(4,1): 1 + 4 + 1 + 1 = 7.0
# Detour  start(0,1)→(0,0)→(1,0)→(2,0)→(3,0)→(4,0)→(4,1): 1+1+1+1+1+1 = 6.0
#   OR    start(0,1)→(0,2)→(1,2)→(2,2)→(3,2)→(4,2)→(4,1): same 6.0
# ---------------------------------------------------------------------------

func test_find_path_cost_optimal_prefers_detour() -> void:
	# Arrange
	var grid := MockGrid.new(5, 3, 1.0)
	grid.set_cost(Vector2i(2, 1), 4.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 1), Vector2i(4, 1), grid)
	# Assert — pathfinder must choose the cheaper detour
	assert_bool(result.found).is_true()
	assert_float(result.cost).is_equal_approx(6.0, 0.001)


func test_find_path_cost_optimal_does_not_go_through_expensive_tile() -> void:
	var grid := MockGrid.new(5, 3, 1.0)
	grid.set_cost(Vector2i(2, 1), 4.0)
	var result := LogisticsPathfinder.find_path(Vector2i(0, 1), Vector2i(4, 1), grid)
	assert_bool(result.path.has(Vector2i(2, 1))).is_false()


# ---------------------------------------------------------------------------
# TC-5 (AC-3, AC-5 edge case) — start == goal
# ---------------------------------------------------------------------------

func test_find_path_start_equals_goal_found_true() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(2, 2), Vector2i(2, 2), grid)
	assert_bool(result.found).is_true()


func test_find_path_start_equals_goal_path_contains_only_start() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(2, 2), Vector2i(2, 2), grid)
	assert_int(result.path.size()).is_equal(1)
	assert_that(result.path[0]).is_equal(Vector2i(2, 2))


func test_find_path_start_equals_goal_cost_zero() -> void:
	var grid := MockGrid.new(5, 5, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(2, 2), Vector2i(2, 2), grid)
	assert_float(result.cost).is_equal(0.0)


# ---------------------------------------------------------------------------
# TC-6 (AC-3, AC-9) — 10×10 flat grid, start(0,0)→goal(9,9), cost==18.0
# ---------------------------------------------------------------------------

func test_find_path_10x10_flat_found_true() -> void:
	var grid := MockGrid.new(10, 10, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(9, 9), grid)
	assert_bool(result.found).is_true()


func test_find_path_10x10_flat_cost_equals_18() -> void:
	# Manhattan distance (0,0)→(9,9) = 18
	var grid := MockGrid.new(10, 10, 1.0)
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(9, 9), grid)
	assert_float(result.cost).is_equal_approx(18.0, 0.001)


# ---------------------------------------------------------------------------
# AC-6 — 4-directional movement only (no diagonals in path steps)
# ---------------------------------------------------------------------------

func test_find_path_no_diagonal_moves_in_path() -> void:
	# Arrange — open 5×5 grid
	var grid := MockGrid.new(5, 5, 1.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(4, 4), grid)
	# Assert — every consecutive step must be axis-aligned (no diagonals)
	for i in range(result.path.size() - 1):
		var from: Vector2i = result.path[i]
		var to: Vector2i = result.path[i + 1]
		var dx: int = abs(to.x - from.x)
		var dy: int = abs(to.y - from.y)
		# A valid 4-directional step has exactly one axis changing by 1
		assert_int(dx + dy).is_equal(1)


# ---------------------------------------------------------------------------
# AC-7 — Out-of-bounds tiles are treated as impassable
# ---------------------------------------------------------------------------

func test_find_path_does_not_expand_oob_tiles() -> void:
	# Arrange — 3×3 grid; start at corner (0,0), goal at (2,2)
	# If OOB were passable the path could escape the grid. Should still find inbounds path.
	var grid := MockGrid.new(3, 3, 1.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(2, 2), grid)
	# Assert — path found and every tile is within bounds
	assert_bool(result.found).is_true()
	for tile: Vector2i in result.path:
		assert_bool(tile.x >= 0 and tile.x < 3 and tile.y >= 0 and tile.y < 3).is_true()


# ---------------------------------------------------------------------------
# AC-4 — path_cost excludes the start tile
# ---------------------------------------------------------------------------

func test_find_path_cost_excludes_start_tile() -> void:
	# Arrange — 1×3 grid, single straight path: (0,0)→(0,1)→(0,2)
	# Each tile costs 1.0. Only (0,1) and (0,2) are entered, so cost should be 2.0.
	var grid := MockGrid.new(3, 3, 1.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(0, 2), grid)
	# Assert
	assert_bool(result.found).is_true()
	assert_float(result.cost).is_equal_approx(2.0, 0.001)


func test_find_path_cost_counts_only_entered_tiles() -> void:
	# Arrange — 1×2 grid: start(0,0)→goal(1,0). One entered tile at cost 1.0.
	var grid := MockGrid.new(5, 1, 1.0)
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(1, 0), grid)
	# Assert — cost is 1.0 (only (1,0) is entered, start (0,0) is free)
	assert_bool(result.found).is_true()
	assert_float(result.cost).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# TC-7 (AC-8) — Performance: 30×30 grid with ~20% random IMPASSABLE, ≤5ms
# ---------------------------------------------------------------------------

func test_find_path_performance_30x30_completes_within_5ms() -> void:
	# Arrange — deterministic seeded random to place ~20% obstacles.
	# Seed chosen to guarantee a path exists from (0,0) to (29,29).
	var grid := MockGrid.new(30, 30, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Block ~20% of interior tiles; leave border rows/columns and corners clear
	# to maximise connectivity and ensure a path exists.
	for x in range(1, 29):
		for y in range(1, 29):
			if rng.randf() < 0.20:
				grid.set_impassable(Vector2i(x, y))

	# Act
	var t_start: int = Time.get_ticks_usec()
	var result := LogisticsPathfinder.find_path(Vector2i(0, 0), Vector2i(29, 29), grid)
	var elapsed_us: int = Time.get_ticks_usec() - t_start

	# Assert — path found and within 5ms (5000 µs)
	assert_bool(result.found).is_true()
	assert_int(elapsed_us).is_less(5000)


# ---------------------------------------------------------------------------
# Regression — road detour must beat direct tree path when roads cost 0.5
# Reproduces the inadmissible-heuristic bug: heuristic assumed min cost = 1.0,
# causing A* to overestimate road detour f-scores and wrongly prefer tree paths.
#
# Layout (5×3, start=(0,1) goal=(4,1)):
#   Row 0: [r][r][r][r][r]   road tiles — cost 0.5 each
#   Row 1: [S][.][T][.][G]   S=start, T=tree cost 4.0, G=goal
#
# Direct  (0,1)→(1,1)→(2,1)→(3,1)→(4,1): 1+4+1+0 = 6.0
# Detour  (0,1)→(0,0)→(1,0)→(2,0)→(3,0)→(4,0)→(4,1): 0.5*5+0 = 2.5  ← optimal
# ---------------------------------------------------------------------------
func test_find_path_road_detour_preferred_over_direct_tree_path() -> void:
	# Arrange
	var grid := MockGrid.new(5, 3, 1.0)
	grid.set_cost(Vector2i(2, 1), 4.0)  # tree blocking direct route
	for x in range(5):
		grid.set_cost(Vector2i(x, 0), 0.5)  # road row above
	# Act
	var result := LogisticsPathfinder.find_path(Vector2i(0, 1), Vector2i(4, 1), grid)
	# Assert — road detour chosen, expensive tree tile avoided
	assert_bool(result.found).is_true()
	assert_bool(result.path.has(Vector2i(2, 1))).is_false()
	assert_float(result.cost).is_equal_approx(2.5, 0.001)
