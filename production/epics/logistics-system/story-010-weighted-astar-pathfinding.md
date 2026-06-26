# Story 010: Weighted A* Pathfinding

> **Epic**: Logistics System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-016`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0013: Tile-Weighted Pathfinding for Logistics Routes
**ADR Decision Summary**: `LogisticsPathfinder` (pure `class_name`, no Node) implements A* with Manhattan heuristic. Returns a `PathResult` value object containing path (Array[Vector2i]), total cost (float), and found (bool). 4-directional movement only. GDScript sorted-array open set (acceptable for 30×30 grid; revisit at 50×50).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — `Dictionary`, `Array[Vector2i]`, `Vector2i` arithmetic are stable since Godot 4.0. `INF` constant is available globally in GDScript.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Visual pool pattern — recycled scene templates, registry owns all state
- Forbidden: Never use TileMap for rendering — always TileMapLayer

---

## Acceptance Criteria

*From ADR-0013, scoped to this story:*

- [ ] `class_name PathResult` exists with fields: `path: Array[Vector2i]`, `cost: float`, `found: bool`
- [ ] `class_name LogisticsPathfinder` exists with static method `find_path(start: Vector2i, goal: Vector2i, grid: GridMap) -> PathResult`
- [ ] `find_path` returns `PathResult` with `found = true` and the optimal (lowest cost) path when a valid path exists
- [ ] `path_cost = Σ get_tile_movement_cost(tile)` for each tile in path **excluding the start tile** (cost paid on entry, not departure)
- [ ] `find_path` returns `PathResult` with `found = false`, empty path, and `cost = 0.0` when no path exists (all routes blocked by IMPASSABLE tiles)
- [ ] Pathfinder uses 4-directional movement only (North, South, East, West — no diagonals)
- [ ] Pathfinder never expands out-of-bounds tiles (treats them as IMPASSABLE)
- [ ] `find_path` runs in ≤5ms for a 30×30 grid (900 tiles) — verified by a performance test in the test suite
- [ ] On a flat map (all movement costs 1.0, no obstacles), `PathResult.cost` equals the Manhattan distance between start and goal

---

## Implementation Notes

*Derived from ADR-0013:*

**File layout**:
```
src/gameplay/logistics_pathfinder.gd   # class_name LogisticsPathfinder
src/gameplay/path_result.gd            # class_name PathResult
```

**PathResult** (pure data, no Node):
```gdscript
class_name PathResult

var path: Array[Vector2i] = []
var cost: float = 0.0
var found: bool = false

static func success(p: Array[Vector2i], c: float) -> PathResult:
    var r := PathResult.new()
    r.path = p; r.cost = c; r.found = true
    return r

static func failure() -> PathResult:
    return PathResult.new()
```

**A* open set**: GDScript has no built-in min-heap. Use a sorted `Array` of `[f_score: float, pos: Vector2i]` pairs, insert in order using `Array.bsearch_custom()` (stable since 4.0). This gives O(n log n) insert and O(1) pop. Acceptable for ≤900 nodes; revisit at 50×50 if profiling shows >5ms.

**Heuristic**: `h(pos, goal) = abs(pos.x - goal.x) + abs(pos.y - goal.y)` (Manhattan, admissible for 4-directional grid).

**Path reconstruction**: Walk `came_from` dictionary from goal back to start, then reverse.

**Key invariant**: The start tile itself is NOT counted in `path_cost` — the carrier is already standing there. Only tiles entered on the way to the goal contribute cost.

**Flat-map equivalence test** (AC last bullet): Create a 10×10 flat grid (all cost 1.0). Assert `find_path((0,0), (9,9)).cost == 18` (Manhattan distance = 9+9 = 18).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 009]: `GridMap.get_tile_movement_cost()` / `is_tile_passable()` — the pathfinder calls these; they must already exist
- [Story 011]: Injecting `LogisticsPathfinder.find_path()` into the carrier FSM and caching results on routes
- [Story 012]: Path invalidation on terrain change

---

## QA Test Cases

*Written by qa-lead at story creation.*

**Basic pathfinding:**

- **AC-1**: Direct path on open grid
  - Given: 5×5 flat grid (all tiles passable, cost 1.0), start (0, 0), goal (4, 4)
  - When: `find_path(Vector2i(0,0), Vector2i(4,4), grid)` is called
  - Then: `found = true`, `cost == 8.0` (Manhattan distance = 4+4 = 8), path starts at (0,0) and ends at (4,4)

- **AC-2**: No path when fully blocked
  - Given: Grid where an IMPASSABLE wall of buildings spans column x=2 from y=0 to y=4, blocking all passage from left half to right half
  - When: `find_path(Vector2i(0, 2), Vector2i(4, 2), grid)` is called
  - Then: `found = false`, `path.size() == 0`, `cost == 0.0`

- **AC-3**: Path routes around a building
  - Given: 5×5 grid; building (IMPASSABLE) at (2, 0), (2, 1), (2, 2), (2, 3) — a gap at (2, 4); start (0, 2), goal (4, 2)
  - When: `find_path` is called
  - Then: `found = true`, returned path passes through (2, 4) (the gap), does NOT include (2, 0)–(2, 3)

- **AC-4**: Cost-optimal path through resource tiles vs. detour
  - Given: 5×3 grid; direct path goes through resource tile at (2, 1) with cost 4.0; alternate path detours 2 tiles around it (cost 2 × 1.0 extra = 2.0 extra); start (0, 1), goal (4, 1)
  - When: `find_path` is called
  - Then: `found = true`, returned path takes the detour (total cost = 6.0) rather than the direct resource path (total cost = 3.0 + 4.0 = 7.0)
  - Note: Detour is (0,1)→(1,1)→(1,0)→(2,0)→(3,0)→(3,1)→(4,1) = cost 6; direct is (0,1)→(1,1)→(2,1)[cost4]→(3,1)→(4,1) = cost 7. Detour wins.

- **AC-5**: Start equals goal
  - Given: Any passable tile at pos (3, 3)
  - When: `find_path(Vector2i(3,3), Vector2i(3,3), grid)` is called
  - Then: `found = true`, `path == [Vector2i(3,3)]`, `cost == 0.0`

- **AC-6**: Flat-map path cost equals Manhattan distance
  - Given: 10×10 flat grid (all tiles passable, all costs 1.0); start (0, 0), goal (9, 9)
  - When: `find_path` is called
  - Then: `found = true`, `cost == 18.0`

**Performance:**

- **AC-7**: 30×30 grid pathfind within 5ms
  - Given: 30×30 grid with random 20% impassable tiles (seeded RNG for determinism); start (0, 0), goal (29, 29) — path must exist
  - When: `find_path` is called and execution time is measured
  - Then: Execution completes in ≤5ms (use `Time.get_ticks_usec()` before and after)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/logistics/astar_pathfinder_test.gd` — must exist and pass

---

## Dependencies

- Depends on: Story 009 (GridMap must expose `get_tile_movement_cost` / `is_tile_passable`)
- Unlocks: Story 011 (route path integration), Story 012 (cached path queries for invalidation)

## Completion Notes
**Completed**: 2026-06-04
**Criteria**: 9/9 passing
**Deviations**: None
**Test Evidence**: Logic — `tests/unit/logistics/astar_pathfinder_test.gd` (27 test functions, all AC-1 through AC-9 covered)
**Code Review**: Skipped (Lean mode)
