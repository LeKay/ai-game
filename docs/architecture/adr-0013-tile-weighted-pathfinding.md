# ADR-0013: Tile-Weighted Pathfinding for Logistics Routes

## Status
Accepted

## Date
2026-06-04

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Feature (Gameplay Systems) |
| **Knowledge Risk** | LOW — pure GDScript data structures; no post-cutoff engine APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/architecture/adr-0004-grid-map-data-model.md`, `docs/architecture/adr-0011-logistics-system.md` |
| **Post-Cutoff APIs Used** | None — A* implementation uses only `Array`, `Dictionary`, `Vector2i` arithmetic |
| **Verification Required** | Verify `Vector2i` hash equality in `Dictionary` key lookup (stable since 4.0). Confirm `Array[Vector2i]` push_back/pop_back performance on 30×30 grid is within 5ms budget. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (GridMap — tile layer data model, 3-layer structure), ADR-0011 (Logistics System — route model, Formula 1, carrier FSM) |
| **Enables** | Road System (roads reduce tile movement cost to 0.5), Terrain Variety (water/swamp tiles with high movement costs), Route Optimization UI (display actual path on map) |
| **Blocks** | None — extends existing logistics stories; stories 001–008 remain valid; path cost replaces Manhattan distance transparently |
| **Ordering Note** | ADR-0013 stories (009–012) must be implemented after Story 002 (carrier FSM) because they replace the distance calculation inside the carrier travel logic |

## Context

### Problem Statement

The Logistics System (ADR-0011) uses Manhattan distance × `ticks_per_tile` as carrier travel time. This works for a flat, obstacle-free map but ignores two gameplay realities:

1. **Resources occupy tiles** — A Lumber Camp surrounded by forest has carriers pushing through dense underbrush. Moving through a resource tile (tree, stone deposit) should be slower than walking across open ground.
2. **Buildings block routes** — Carriers cannot physically walk through a building. A route that used Manhattan distance might implicitly cross a building's tile, producing incorrect travel times and invisible routing.

The existing GDD asks "Should the Logistics System reserve an interface for road-based travel time reduction?" (Open Question 2). This ADR answers that question by establishing a generalised tile movement cost system that already accounts for roads as a future case.

### Constraints

- No runtime resizing — grid remains 30×30 for Vertical Slice.
- A* must run in ≤5ms on a 30×30 grid (900 tiles) — verified during implementation.
- Path data is cached per route; recalculated only on terrain change (not every tick).
- 4-directional movement only (North/South/East/West) — consistent with the Manhattan-distance grid model already in ADR-0004 and ADR-0009.
- Buildings in BuildingLayer are always IMPASSABLE — no exceptions.
- Formula 1 is updated but not replaced: `path_cost` takes the place of `distance`, and the formula structure stays the same.

### Requirements

- TR-logistics-015: GridMap exposes `get_tile_movement_cost(pos)` and `is_tile_passable(pos)` queried by the pathfinder
- TR-logistics-016: A* pathfinder returns optimal path (Array[Vector2i]) and total path cost (float) for any source → destination pair
- TR-logistics-017: Route creation is blocked if A* finds no viable path; descriptive error is returned
- TR-logistics-018: Cached paths are invalidated and routes recalculated when terrain changes (building placed/demolished, resource depleted/added)

## Decision

### Tile Movement Cost Model

Each tile's movement cost is resolved by `GridMap.get_tile_movement_cost(pos: Vector2i) -> float` using priority-ordered layer checks:

| Check | Cost | Rationale |
|-------|------|-----------|
| BuildingLayer occupied | `INF` (impassable) | A carrier cannot walk through a building |
| ResourceLayer occupied (tree, stone deposit, etc.) | `4.0` | Dense terrain — very slow to push through |
| TerrainLayer (open grass, dirt) | `1.0` | Normal movement |
| Road tile (future, reserved) | `0.5` | Paved surface — faster than open ground |

`is_tile_passable(pos) -> bool` returns `false` if `get_tile_movement_cost(pos) == INF`.

The cost model is data-driven: resource tile costs are defined in `data/resources.json` under a new `movement_cost` field. Building impassability is always enforced regardless of resource data.

### Pathfinding Algorithm: A\* with Manhattan Heuristic

A* is chosen over Dijkstra (exhaustive) and BFS (unweighted) because:
- **A* with Manhattan heuristic is admissible** on a 4-directional grid: `h(n) = |n.x - goal.x| + |n.y - goal.y|`. This guarantees the optimal path is found first.
- **Faster than Dijkstra** on directed searches (typical start-to-goal logistics route) because the heuristic prunes nodes far from the goal.
- **BFS cannot handle movement costs** — it treats all tiles as equal weight.

Implementation class: `LogisticsPathfinder` (pure `class_name`, no Node inheritance). Stateless — called once per path request, returns a `PathResult` value object.

```
class_name PathResult
var path: Array[Vector2i]  # ordered list of tile positions, source → destination
var cost: float            # total movement cost (Σ movement_cost per tile in path, excluding source)
var found: bool            # false if no path exists
```

A* pseudocode (4-directional, no diagonals):
```
open_set = MinHeap keyed by f = g + h
closed_set = Dictionary[Vector2i, bool]
g_score = Dictionary[Vector2i, float]  # cost from start
came_from = Dictionary[Vector2i, Vector2i]

g_score[start] = 0
push(open_set, start, h(start, goal))

while open_set not empty:
    current = pop_min(open_set)
    if current == goal: reconstruct_path; return PathResult(path, g_score[goal], true)
    closed_set[current] = true
    for neighbor in [N, S, E, W]:
        if not in_bounds(neighbor) or not is_passable(neighbor) or closed_set[neighbor]: skip
        tentative_g = g_score[current] + get_tile_movement_cost(neighbor)
        if tentative_g < g_score.get(neighbor, INF):
            came_from[neighbor] = current
            g_score[neighbor] = tentative_g
            push(open_set, neighbor, tentative_g + h(neighbor, goal))

return PathResult([], 0.0, false)  # no path found
```

GDScript does not have a built-in min-heap. The implementation uses a sorted `Array` insert (acceptable on 30×30 = 900 tiles; revisit for 50×50 MVP if profiling shows bottleneck).

### Updated Formula 1

Formula 1 is extended to use path cost rather than Manhattan distance:

**Original**: `carrier_travel_ticks = floor(distance × ticks_per_tile)`  
**Updated**: `carrier_travel_ticks = floor(path_cost × ticks_per_tile)`

where `path_cost = Σ movement_cost(tile)` for all tiles in the path **excluding the starting tile**. For a flat map (all tiles cost 1.0), `path_cost == Manhattan distance`, so the formula degrades gracefully to the original behavior.

Round-trip formula (Formula 1 full form) is updated analogously: each leg uses its own A*-computed path cost.

### Path Caching

Each `LogisticsRoute` stores:
```
var cached_path: Array[Vector2i]
var cached_path_cost: float
var path_valid: bool
```

Paths are computed once at route creation and stored. They are recomputed only when:
- A building is placed or demolished (BuildingLayer change)
- A resource tile is added or removed (ResourceLayer change)

`GridMap` emits a new signal `terrain_changed(pos: Vector2i, layer: int)`. The `LogisticsSystem` subscribes and iterates active routes to find those whose `cached_path` contains `pos`, marks them `path_valid = false`, and queues a recalculation.

If recalculation finds no path (`PathResult.found == false`), the route transitions to DEACTIVATED and the player is notified.

### Route Creation Gate

During `create_route()`, after slot validation, the pathfinder is called once:
```
var result = LogisticsPathfinder.find_path(source_pos, dest_pos, grid_map)
if not result.found:
    return FAILURE("No viable path between [source_name] and [destination_name]. Check for blocking buildings.")
```

This prevents the player from creating phantom routes that would never complete a trip.

## Consequences

### Positive
- Spatial gameplay depth: placing a Lumber Camp inside a dense forest now has a real cost (slow carrier egress). Players must think about corridor access when placing extraction buildings.
- Buildings as true obstacles: the player can accidentally block routes by placing a new building between two existing connected buildings. This surfaces as a route DEACTIVATED event with a clear message.
- Road system is fully pre-wired: adding roads later only requires setting `movement_cost = 0.5` on road tiles and calling `terrain_changed`.

### Negative
- Increased route creation cost: one A* call per route creation (≤5ms; negligible for player-paced creation).
- Path cache invalidation complexity: all active routes must be checked on every terrain change. On a 30×30 grid with ≤50 routes this is O(50 × path_length) — acceptable. Revisit for 50×50 MVP.
- Formula 1 examples in GDD and ADR-0011 use flat-map values — they remain correct (flat map path_cost == Manhattan distance) but must be annotated that resource tiles change the cost.

### Neutral
- Stories 001–008 are not invalidated. The change is isolated to the distance/cost calculation inside TRAVEL_TO_SOURCE, TRAVEL_TO_DESTINATION, and RETURN_HOME states. Story 002 (carrier FSM) will need a targeted patch in Story 011 to swap the distance call.

## GDD Requirements Addressed

| TR-ID | Requirement |
|-------|-------------|
| TR-logistics-015 | GridMap `get_tile_movement_cost` / `is_tile_passable` interface |
| TR-logistics-016 | A* pathfinder with path + cost output |
| TR-logistics-017 | Route creation gate — blocked if no path found |
| TR-logistics-018 | Path invalidation and recalculation on terrain change |
