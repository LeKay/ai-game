class_name LogisticsPathfinder
## Weighted A* pathfinder for the logistics system.
## ADR-0013: 4-directional movement, Manhattan heuristic, cost-weighted tiles.
## Pure class — no Node inheritance. Stateless: use find_path() directly.

const _DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),  # North
	Vector2i(0, 1),   # South
	Vector2i(-1, 0),  # West
	Vector2i(1, 0),   # East
]


## Finds the lowest-cost path from start to goal on the given grid using A*.
##
## grid must implement:
##   get_tile_movement_cost(pos: Vector2i) -> float  (returns INF for impassable/OOB)
##   is_tile_passable(pos: Vector2i) -> bool
##
## Parameter grid is intentionally untyped to allow MockGrid in unit tests
## without requiring WorldGrid inheritance (duck-typed interface).
##
## Returns PathResult.success with path [start..goal] and Σ entered-tile costs,
## or PathResult.failure() when no path exists.
static func find_path(start: Vector2i, goal: Vector2i, grid) -> PathResult:
	# Edge case: start equals goal — zero-cost trivial path.
	if start == goal:
		var trivial: Array[Vector2i] = [start]
		return PathResult.success(trivial, 0.0)

	# open_set entries: [f_score: float, pos: Vector2i]
	# Maintained in ascending f_score order via sort after each push.
	var open_set: Array = []

	# closed_set: Vector2i → true for already-expanded nodes.
	var closed_set: Dictionary = {}

	# g_score: Vector2i → float (cost from start to that tile, start = 0.0).
	var g_score: Dictionary = {}

	# came_from: Vector2i → Vector2i (parent tile for path reconstruction).
	var came_from: Dictionary = {}

	g_score[start] = 0.0
	open_set.append([_heuristic(start, goal), start])

	while not open_set.is_empty():
		var entry: Array = open_set.pop_front()
		var current: Vector2i = entry[1]

		# Goal reached — reconstruct and return the path.
		if current == goal:
			return PathResult.success(_reconstruct_path(came_from, start, goal), g_score[goal])

		# Skip nodes already expanded (can appear multiple times in open_set).
		if closed_set.has(current):
			continue
		closed_set[current] = true

		for dir: Vector2i in _DIRECTIONS:
			var neighbor: Vector2i = current + dir

			# Goal tile is always reachable — the carrier enters the destination building
			# regardless of its passability cost. Non-goal impassable tiles are skipped.
			if neighbor != goal and not grid.is_tile_passable(neighbor):
				continue

			# Skip already-expanded neighbors.
			if closed_set.has(neighbor):
				continue

			# Arriving at the goal has no tile movement cost (building entry).
			var move_cost: float = 0.0 if neighbor == goal else grid.get_tile_movement_cost(neighbor)
			var tentative_g: float = g_score[current] + move_cost

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f: float = tentative_g + _heuristic(neighbor, goal)
				open_set.append([f, neighbor])
				# Keep open_set sorted ascending by f_score for O(1) pop_front().
				open_set.sort_custom(func(a: Array, b: Array) -> bool:
					return a[0] < b[0]
				)

	return PathResult.failure()


## Minimum tile movement cost in the grid — must match the cheapest passable tile
## (road tile = 0.5, defined in WorldGrid.get_tile_movement_cost).
## Scaling the heuristic by this value keeps it admissible when tile costs < 1.0.
const MIN_TILE_COST: float = 0.5

## Manhattan distance heuristic scaled by the minimum possible tile cost.
## Admissible on weighted grids with tile costs >= MIN_TILE_COST.
static func _heuristic(pos: Vector2i, goal: Vector2i) -> float:
	return float(abs(pos.x - goal.x) + abs(pos.y - goal.y)) * MIN_TILE_COST


## Reconstructs the path array by walking came_from from goal back to start,
## then reversing. Resulting array starts at start and ends at goal.
static func _reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector2i = goal
	while current != start:
		path.append(current)
		current = came_from[current]
	path.append(start)
	path.reverse()
	return path
