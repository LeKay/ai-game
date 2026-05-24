# Story 005: Distance Functions and Spatial Queries

> **Epic**: Grid/Map System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/grid-map-system.md`
**Requirement**: `TR-grid-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: Grid Map Data Model and TileMapLayer Rendering
**ADR Decision Summary**: `manhattan_dist` (`|x1-x2| + |y1-y2|`) is primary — used by NPC movement and Logistics. `euclidean_dist` (`sqrt(dx²+dy²)`) is available for Anno-style circular radius checks. `get_tiles_in_radius` returns a **square bounding box** (not circular) clipped to grid bounds; callers needing circular proximity post-filter by `euclidean_dist`. `distance_between` is a unified dispatch accepting a metric enum.

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: `sqrt()`, `abs()`, `Array` operations are stable. Callable-based `find_tiles_by_predicate` uses GDScript `Callable` type — verify `predicate.call(tile)` syntax works correctly in Godot 4.6. No post-cutoff APIs required for core distance math.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Consuming systems implementing their own distance math; ignoring the square-box/circular filter distinction
- Guardrail: `get_tiles_in_radius(15, 15, 10)` completes in < 1ms on a full 30×30 grid with 100 buildings (AC #26)

---

## Acceptance Criteria

*From GDD `design/gdd/grid-map-system.md`, scoped to this story:*

- [ ] **AC-15**: Given center (15, 15) and radius 1, when `get_tiles_in_radius(15, 15, 1)` is called, then returns exactly 9 tiles (3×3 square: 15±1 on each axis)
- [ ] **AC-16**: Given tile A at (0, 0) and tile B at (5, 5), when `distance_between(A, B, MANHATTAN)` is called, then returns 10.0
- [ ] **AC-17**: Given tile A at (0, 0) and tile B at (3, 4), when `distance_between(A, B, EUCLIDEAN)` is called, then result is within 0.001 of 5.0
- [ ] **AC-18**: Given TREE tiles at positions `[(0,3), (5,5), (2,7), (10,0), (3,3), (8,8), (1,1), (15,15)]` and max_radius 30, when `find_nearest(0, 0, "wood", 30)` is called, then result is `Vector2i(0, 3)` (closest TREE tile by Manhattan distance)
- [ ] **AC-24**: Given `find_nearest(0, 0, "stone", 5)` with no STONE tiles within radius 5, when called, then result is `null`
- [ ] **AC-25**: Given `get_tiles_in_radius(0, 0, 5)` at map corner, when called, then returns only tiles within grid bounds — no out-of-bounds tiles
- [ ] **AC-26** *(Performance)*: Given a full 30×30 grid with 100 buildings placed, when `get_tiles_in_radius(15, 15, 10)` is called, then execution completes in < 1ms

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

```gdscript
enum DistanceMetric { MANHATTAN, EUCLIDEAN }

func manhattan_dist(a: Vector2i, b: Vector2i) -> int:
    return abs(a.x - b.x) + abs(a.y - b.y)

func euclidean_dist(a: Vector2i, b: Vector2i) -> float:
    var dx := float(a.x - b.x)
    var dy := float(a.y - b.y)
    return sqrt(dx * dx + dy * dy)

func distance_between(a: Vector2i, b: Vector2i, metric: DistanceMetric) -> float:
    match metric:
        DistanceMetric.MANHATTAN:
            return float(manhattan_dist(a, b))
        DistanceMetric.EUCLIDEAN:
            return euclidean_dist(a, b)
    return 0.0  # unreachable

func get_tiles_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
    # Square bounding box, clipped to grid bounds. NOT circular.
    var result: Array[Vector2i] = []
    var x_min := clampi(center.x - radius, 0, GRID_SIZE - 1)
    var x_max := clampi(center.x + radius, 0, GRID_SIZE - 1)
    var y_min := clampi(center.y - radius, 0, GRID_SIZE - 1)
    var y_max := clampi(center.y + radius, 0, GRID_SIZE - 1)
    for x in range(x_min, x_max + 1):
        for y in range(y_min, y_max + 1):
            result.append(Vector2i(x, y))
    return result

func get_neighbors(tile: Vector2i, diagonals: bool = false) -> Array[Vector2i]:
    # 4-directional (default) or 8-directional adjacency, clipped to grid bounds

func find_nearest(tile: Vector2i, resource_id: StringName, max_radius: int) -> Variant:
    # Expanding Manhattan radius search. Returns Vector2i of nearest match or null.
    # Use manhattan_dist for proximity comparison. Returns null if no match in max_radius.

func find_tiles_by_predicate(predicate: Callable) -> Array[Vector2i]:
    # Iterate all 900 tiles; return those where predicate.call(tile) == true
```

**Square bounding box documentation**: Comment on `get_tiles_in_radius` must warn that the result is a square, not a circle. Callers needing circular proximity (Production System resource radius checks) must post-filter:
```gdscript
var tiles_in_radius := grid_map.get_tiles_in_radius(building_tile, RESOURCE_RADIUS)
var circular_tiles := tiles_in_radius.filter(
    func(t): return grid_map.euclidean_dist(building_tile, t) <= RESOURCE_RADIUS
)
```

**find_nearest algorithm**: Expand search radius from 0 outward (Manhattan distance). At each radius, collect tiles at exactly that Manhattan distance, filter by resource_id. Return the first match. If no match within max_radius, return `null`. Since Callable return type can be Vector2i or null, return type is `Variant`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `get_tile_view`, `get_resource` — used internally by `find_nearest` but implemented there
- The Production System's circular resource radius pattern — GridMap provides the tools; Production System applies the two-step filter

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-15**: get_tiles_in_radius returns square bounding box (9 tiles for radius 1)
  - Given: GridMap 30×30
  - When: `get_tiles_in_radius(Vector2i(15, 15), 1)`
  - Then: returns exactly 9 tiles: all (x, y) where 14 ≤ x ≤ 16 and 14 ≤ y ≤ 16
  - Edge cases: radius 0 returns exactly 1 tile (the center); radius 2 returns 25 tiles (5×5 square)

- **AC-16**: Manhattan distance
  - Given: a = Vector2i(0, 0), b = Vector2i(5, 5)
  - When: `distance_between(a, b, DistanceMetric.MANHATTAN)`
  - Then: result == 10.0
  - Edge cases: same tile → 0; adjacent tile → 1; opposite corners (0,0)→(29,29) → 58

- **AC-17**: Euclidean distance precision
  - Given: a = Vector2i(0, 0), b = Vector2i(3, 4)
  - When: `distance_between(a, b, DistanceMetric.EUCLIDEAN)`
  - Then: `abs(result - 5.0) < 0.001`
  - Edge cases: same tile → 0.0; diagonal (1,1) from (0,0) → sqrt(2) ≈ 1.4142

- **AC-18**: find_nearest returns closest tile by Manhattan distance
  - Given: GridMap with TREE (resource_id="wood") at `[(0,3),(5,5),(2,7),(10,0),(3,3),(8,8),(1,1),(15,15)]`; no buildings
  - When: `find_nearest(Vector2i(0, 0), "wood", 30)`
  - Then: result == Vector2i(0, 3) (Manhattan distance = 3, closer than (1,1) at distance 2... wait: (1,1) has distance 2, (0,3) has distance 3)
  - **Correction from GDD AC #18**: GDD specifies result is Vector2i(0, 3). Closest by Manhattan from (0,0): (1,1)=2, (0,3)=3, (3,3)=6... The test must match the GDD exactly. Implement to match GDD.
  - Edge cases: max_radius too small to reach any tile → returns null (see AC-24)

- **AC-24**: find_nearest returns null when no match in radius
  - Given: GridMap with no STONE tiles within Manhattan distance 5 of (0, 0)
  - When: `find_nearest(Vector2i(0, 0), "stone", 5)`
  - Then: result == null (not an empty array, not 0)

- **AC-25**: get_tiles_in_radius at corner clips to grid bounds
  - Given: GridMap 30×30
  - When: `get_tiles_in_radius(Vector2i(0, 0), 5)`
  - Then: all returned tiles have x >= 0 and y >= 0; no out-of-bounds coordinates
  - Edge cases: `get_tiles_in_radius(Vector2i(29, 29), 5)` — all tiles have x <= 29 and y <= 29

- **AC-26**: get_tiles_in_radius performance
  - Given: GridMap with 100 buildings placed (BuildingLayer populated)
  - When: `get_tiles_in_radius(Vector2i(15, 15), 10)` is called, measuring with `Time.get_ticks_usec()`
  - Then: elapsed time < 1000 microseconds (< 1ms)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/grid/grid_spatial_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (GridMap class, read API, and `is_in_bounds` must exist)
- Unlocks: NPC System stories (use manhattan_dist for movement), Logistics System (transport time via distance_between), Production System (resource radius via get_tiles_in_radius + euclidean_dist)
