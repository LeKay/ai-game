# Story 012: Path Invalidation on Terrain Change

> **Epic**: Logistics System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-018`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0013: Tile-Weighted Pathfinding for Logistics Routes
**ADR Decision Summary**: `LogisticsSystem` subscribes to `GridMap.terrain_changed(pos, layer)`. On each change: iterate active routes; any route whose `cached_path` contains `pos` is marked `path_valid = false` and queued for recalculation. Recalculation runs at end-of-frame. If no new path found → route DEACTIVATED. If new path found → route continues with updated cost, carrier travel times adjusted from next state transition.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — signal subscription, Array iteration, and Dictionary access are stable since Godot 4.0.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Visual pool pattern — recycled scene templates, registry owns all state
- Forbidden: Never use TileMap for rendering — always TileMapLayer
- Forbidden: Never read tile state from TileMapLayer — always from GridMap data model

---

## Acceptance Criteria

*From ADR-0013, scoped to this story:*

- [ ] `LogisticsSystem` subscribes to `GridMap.terrain_changed` signal on initialization
- [ ] When `terrain_changed(pos, layer)` fires, all active routes whose `cached_path` contains `pos` are marked `path_valid = false`
- [ ] Marked routes are recalculated (A* re-run) at end of the same frame; routes not containing `pos` are unaffected
- [ ] If recalculation succeeds (`PathResult.found == true`): route's `cached_path` and `cached_path_cost` are updated; `path_valid = true`; carrier travel times update at the next state transition (in-flight carriers complete the current leg using the old cost, then use the new cost for subsequent legs)
- [ ] If recalculation fails (`PathResult.found == false`): route transitions to DEACTIVATED; any carrier mid-trip completes its current leg then returns home (same behavior as EC-L4 in the GDD)
- [ ] A route newly unblocked by building demolition (previously DEACTIVATED due to blocked path) is NOT automatically reactivated — the player must manually reactivate it. The route's stored path becomes valid again but lifecycle state stays DEACTIVATED until player action
- [ ] Routes with `path_valid = false` that are currently in a WAITING_SOURCE or WAITING_DESTINATION state do not immediately interrupt the wait — interruption happens at the next carrier state transition

---

## Implementation Notes

*Derived from ADR-0013:*

**Signal subscription** (in `LogisticsSystem._ready()`):
```gdscript
GridMap.terrain_changed.connect(_on_terrain_changed)
```

**Invalidation handler**:
```gdscript
func _on_terrain_changed(pos: Vector2i, _layer: int) -> void:
    for route in _active_routes.values():
        if route.cached_path.has(pos):
            route.path_valid = false
    _recalculate_invalid_paths.call_deferred()
```

**Recalculation** (deferred to end of frame to avoid mid-tick mutations):
```gdscript
func _recalculate_invalid_paths() -> void:
    for route in _active_routes.values():
        if route.path_valid:
            continue
        var result = LogisticsPathfinder.find_path(
            _get_building_pos(route.source_building_id),
            _get_building_pos(route.destination_building_id),
            _grid_map
        )
        if result.found:
            route.cached_path = result.path
            route.cached_path_cost = result.cost
            route.path_valid = true
        else:
            _deactivate_route_blocked(route)
```

**In-flight carrier behavior**: Do NOT interrupt a carrier that is currently counting down `remaining_ticks`. The updated path cost takes effect only when the carrier enters a new travel state (on next trip start). This avoids teleportation artifacts where a carrier is mid-route when the terrain changes.

**DEACTIVATED route on unblock**: The `path_valid` flag tracks path viability, not lifecycle state. A DEACTIVATED route can have `path_valid = true` after terrain is cleared — the player still must explicitly reactivate it. This maintains the design principle that route management is player-driven (GDD Core Rules 2).

**Performance note**: On a 30×30 grid with ≤50 routes and typical paths of ≤30 tiles, the `Array.has()` check per route per terrain change is O(50 × 30) = O(1500) comparisons — negligible. Do not add a spatial index unless profiling proves it necessary.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 009]: `terrain_changed` signal definition and emission
- [Story 010]: A* pathfinder implementation
- [Story 011]: Route path caching (`cached_path`, `path_valid` fields)
- Route visualization updates when path changes — deferred to a future route-visualization update story

---

## QA Test Cases

*Written by qa-lead at story creation.*

**Terrain change invalidation:**

- **AC-1**: Building placement invalidates affected route
  - Given: Active route from (0,0) to (8,0); cached path passes through (4,0); `path_valid = true`
  - When: A building is placed at (4,0) — `terrain_changed(Vector2i(4,0), BUILDING_LAYER)` fires
  - Then: Route's `path_valid == false` immediately after signal; unaffected routes (not through (4,0)) remain `path_valid = true`

- **AC-2**: Successful recalculation updates path
  - Given: Same scenario as AC-1; an open detour exists around (4,0) via (4,1)
  - When: `_recalculate_invalid_paths()` runs
  - Then: Route's `path_valid == true`; `cached_path` does not include (4,0); `cached_path_cost` reflects the new detour cost

- **AC-3**: Route deactivated when no detour exists
  - Given: Active route from (0,2) to (8,2); IMPASSABLE buildings placed at (4,0) through (4,4) — complete barrier, no gap
  - When: Last building placed at (4,2); recalculation runs
  - Then: Route's `lifecycle_state == DEACTIVATED`; `path_valid == false`

- **AC-4**: Building demolition does not auto-reactivate DEACTIVATED route
  - Given: Route DEACTIVATED because building blocked the only path (AC-3 scenario)
  - When: The blocking building at (4,2) is demolished; `terrain_changed` fires; recalculation runs
  - Then: Route's `path_valid == true` (path now exists); `lifecycle_state == DEACTIVATED` (still — player must reactivate); `cached_path` is updated

- **AC-5**: In-flight carrier completes current leg with old cost
  - Given: Active route; carrier in TRAVEL_TO_DESTINATION with `remaining_ticks = 10`; resource tile on the path is removed (tile becomes open, cost drops from 4.0 to 1.0); recalculation updates `cached_path_cost`
  - When: Carrier continues counting down `remaining_ticks` for the current leg
  - Then: Carrier finishes the current leg using the original `remaining_ticks = 10` (not recalculated mid-leg); new path cost is used starting with the next TRAVEL state entry

- **AC-6**: Unrelated routes unaffected by terrain change
  - Given: Route A passes through (4,0); Route B passes through (7,7); building placed at (4,0)
  - When: `terrain_changed(Vector2i(4,0), BUILDING_LAYER)` fires
  - Then: Route A `path_valid == false`; Route B `path_valid == true` (unchanged)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/logistics/path_invalidation_test.gd` — must exist and pass

---

## Dependencies

- Depends on: Story 009 (`terrain_changed` signal), Story 010 (A* pathfinder), Story 011 (route caches `cached_path` and `path_valid`)
- Unlocks: No further dependency — this completes the tile-weighted pathfinding feature arc (Stories 009–012)

---

## Completion Notes
**Completed**: 2026-06-05
**Criteria**: 7/7 passing
**Deviations**: None
**Test Evidence**: Integration test at `tests/integration/logistics/path_invalidation_test.gd` (8 test functions, AC-1 through AC-7 covered)
**Code Review**: Skipped — Lean mode
