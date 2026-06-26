class_name PathResult
## Pure data value object returned by LogisticsPathfinder.find_path().
## Represents either a successful path with its cost, or a failure (no path found).
## ADR-0013: PathResult is a plain GDScript object — no Node inheritance.

## Ordered list of tile positions from start to goal (inclusive of both endpoints).
var path: Array[Vector2i] = []

## Total movement cost of the path. Equals the sum of get_tile_movement_cost()
## for each tile entered (neighbors), excluding the start tile. Zero when found=false.
var cost: float = 0.0

## True when a valid path from start to goal was found; false when fully blocked.
var found: bool = false


## Factory: constructs a successful PathResult with the given path and cost.
static func success(p: Array[Vector2i], c: float) -> PathResult:
	var r := PathResult.new()
	r.path = p
	r.cost = c
	r.found = true
	return r


## Factory: constructs a failure PathResult (found=false, empty path, cost=0.0).
static func failure() -> PathResult:
	return PathResult.new()
