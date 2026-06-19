class_name PathGeometry
## Stateless polyline math for world-space paths (Array[Vector2]).
##
## Centralises the path-length and point-along-path helpers that were previously
## duplicated in MapRoot and RouteLines. All methods are pure and unit-testable.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 1).


## Total length of a polyline (sum of segment lengths). Returns 0.0 for paths with
## fewer than two points.
static func length(path: Array[Vector2]) -> float:
	var total: float = 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


## Returns the point at arc-length `t` (in pixels) along the polyline.
## Clamps to the final point when `t` exceeds the total length.
static func point_along(path: Array[Vector2], t: float) -> Vector2:
	var remaining: float = t
	for i in range(path.size() - 1):
		var seg_len: float = path[i].distance_to(path[i + 1])
		if remaining <= seg_len or i == path.size() - 2:
			return path[i].lerp(path[i + 1], clampf(remaining / seg_len, 0.0, 1.0))
		remaining -= seg_len
	return path[path.size() - 1]
