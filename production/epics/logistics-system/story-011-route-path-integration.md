# Story 011: Logistics Route Path Integration

> **Epic**: Logistics System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-016`, `TR-logistics-017`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0013: Tile-Weighted Pathfinding for Logistics Routes
**ADR Decision Summary**: Carrier FSM travel time (TRAVEL_TO_SOURCE, TRAVEL_TO_DESTINATION, RETURN_HOME) is updated to use `path_cost × ticks_per_tile` instead of `manhattan_distance × ticks_per_tile`. Each route caches its A*-computed path and path cost at creation. Route creation is blocked if no viable path exists. Formula 1 is updated in place — its structure is preserved, only the distance variable is replaced by path_cost.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — changes are confined to GDScript data flow within existing carrier FSM.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Carrier travel time formula — now `carrier_travel_ticks = floor(path_cost × ticks_per_tile)`
- Required: Visual pool pattern — recycled scene templates, registry owns all state
- Forbidden: Never use TileMap for rendering — always TileMapLayer

---

## Acceptance Criteria

*From ADR-0013, scoped to this story:*

- [ ] `LogisticsRoute` gains three new fields: `cached_path: Array[Vector2i]`, `cached_path_cost: float`, `path_valid: bool`
- [ ] During `create_route()`, `LogisticsPathfinder.find_path()` is called; the resulting path and cost are stored in the route; `path_valid = true`
- [ ] `create_route()` returns FAILURE with message `"No viable path between [source_name] and [destination_name]. Check for blocking buildings."` if `PathResult.found == false`
- [ ] The carrier FSM uses `cached_path_cost` (not Manhattan distance) to compute `remaining_ticks` when entering TRAVEL_TO_SOURCE, TRAVEL_TO_DESTINATION, and RETURN_HOME states
- [ ] Formula 1 (round-trip ticks) produces the same result as before on a flat map: `path_cost == Manhattan distance` when no resource tiles or buildings obstruct the path
- [ ] A route created between two buildings separated by a resource tile (cost 4.0) has `carrier_travel_ticks = floor(4.0 × ticks_per_tile)` for that leg — i.e., 4× slower than crossing open ground
- [ ] A route whose path passes through a line of resource tiles (e.g., forest belt) either takes the costly direct path or, if a cheaper detour exists, takes the detour — whichever A* deems optimal

---

## Implementation Notes

*Derived from ADR-0013:*

**LogisticsRoute field additions** (in `src/gameplay/logistics_route.gd`):
```gdscript
var cached_path: Array[Vector2i] = []
var cached_path_cost: float = 0.0
var path_valid: bool = false
```

**`create_route()` updated flow** (in `LogisticsSystem`):
```
validate slot availability (existing)
→ call LogisticsPathfinder.find_path(source_pos, dest_pos, grid_map)
→ if not result.found: return FAILURE("No viable path…")
→ call LogisticsRoute.create(…)
→ route.cached_path = result.path
→ route.cached_path_cost = result.cost
→ route.path_valid = true
```

**Carrier FSM travel leg calculation** — update the three travel states in `_process_carrier(route)` (Story 002):
- `TRAVEL_TO_SOURCE`: `remaining_ticks = floor(path_cost_home_to_source × ticks_per_tile)`
- `TRAVEL_TO_DESTINATION`: `remaining_ticks = floor(route.cached_path_cost × ticks_per_tile)`
- `RETURN_HOME`: `remaining_ticks = floor(path_cost_dest_to_home × ticks_per_tile)`

For home-leg costs: compute `LogisticsPathfinder.find_path(dest_pos, home_pos, grid_map)` at route creation and store as `cached_path_cost_return`. The round trip stores two path costs (outbound and return) since they may differ if the terrain is asymmetric (it is not in MVP, but the architecture supports it).

**Minimal surface area**: Do NOT refactor Story 002's carrier FSM beyond the targeted swap of `distance → cached_path_cost`. All other FSM logic remains unchanged.

**Path positions for each leg**:
- Home → Source: path from NPC home position to source building tile
- Source → Destination: path from source building tile to destination building tile (this is `cached_path`)
- Destination → Home: path from destination building tile to NPC home position

All three are computed once at route creation and cached. If the home leg shares tiles with the source-to-destination path, they are still stored independently.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 009]: GridMap movement cost interface
- [Story 010]: A* pathfinder implementation
- [Story 012]: Reacting to terrain changes (path invalidation and recalculation) — this story assumes paths never change after creation

---

## QA Test Cases

*Written by qa-lead at story creation.*

**Route creation with path:**

- **AC-1**: Route creation stores path and cost
  - Given: Source building at (2, 2), destination at (8, 2), flat map (all cost 1.0), `ticks_per_tile = 3.0`
  - When: `create_route(source_id, dest_id, npc_id, RouteType.OUTPUT)` is called
  - Then: Route is created; `route.cached_path.size() > 0`; `route.cached_path_cost == 6.0` (6 tiles to cross); `route.path_valid == true`

- **AC-2**: Route creation blocked when no path
  - Given: Source building at (0, 0), destination at (10, 0); IMPASSABLE column of buildings at x=5 spans entire grid height (no gap)
  - When: `create_route(…)` is called
  - Then: Returns FAILURE; `get_active_routes().size() == 0`; error message contains both building names

**Travel time from path cost:**

- **AC-3**: Travel ticks use cached_path_cost, not Manhattan distance
  - Given: Source at (0, 0), destination at (4, 0); resource tile at (2, 0) with cost 4.0; detour path cost = 6.0 (goes around resource); direct path cost = 1+4+1 = 6.0 (same, so either chosen); `ticks_per_tile = 3.0`
  - Setup: Create route; activate it (carrier enters TRAVEL_TO_DESTINATION)
  - When: Check `route.remaining_ticks` immediately after state transition to TRAVEL_TO_DESTINATION
  - Then: `remaining_ticks == floor(6.0 × 3.0) == 18`

- **AC-4**: Flat map produces same result as original Manhattan formula
  - Given: Source at (0, 0), destination at (10, 0), flat map (all cost 1.0), `ticks_per_tile = 3.0`
  - When: Route created, carrier enters TRAVEL_TO_DESTINATION
  - Then: `remaining_ticks == floor(10.0 × 3.0) == 30` (matches the original Manhattan formula)

- **AC-5**: Resource belt doubles travel time
  - Given: Source at (0, 2), destination at (4, 2); resource tiles at (1, 2), (2, 2), (3, 2) (all cost 4.0); no detour available (walls on y=1 and y=3); `ticks_per_tile = 3.0`
  - When: Route created, carrier enters TRAVEL_TO_DESTINATION
  - Then: `remaining_ticks == floor((1.0 + 4.0 + 4.0 + 4.0 + 1.0) × 3.0) == floor(14.0 × 3.0) == 42`
  - Note: First tile entered costs 1.0 (before first resource), then 3 resource tiles at 4.0 each, then 1.0 last tile = 10.0 total? Wait, start tile NOT counted. Destination tile IS counted.
    Path: (0,2)→(1,2)[1.0]→(2,2)[4.0]→(3,2)[4.0]→(4,2)[4.0] — wait, (1,2),(2,2),(3,2) are resource tiles. Let me recheck.
    Path visits (0,2) start (not counted), (1,2) cost 4.0, (2,2) cost 4.0, (3,2) cost 4.0, (4,2) cost 1.0 = 13.0 total
    `remaining_ticks == floor(13.0 × 3.0) == 39`

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/logistics/route_path_integration_test.gd` — must exist and pass

---

## Dependencies

- Depends on: Story 009 (GridMap movement cost), Story 010 (A* pathfinder), Story 002 (carrier FSM to patch)
- Unlocks: Story 012 (path invalidation uses `cached_path` to detect affected routes)

---

## Completion Notes
**Completed**: 2026-06-05
**Criteria**: 7/7 passing
**Deviations**:
- ADVISORY: Story Implementation Notes referenced `src/gameplay/logistics_route.gd`; actual file is at `src/systems/logistics/logistics_route.gd`. Correct path used in implementation.
- ADVISORY: AC listed 3 required fields; implementation adds 4 more (`cached_path_cost_home_to_source`, `cached_path_cost_source_to_home`, `cached_path_cost_dest_to_home`, `home_legs_valid`) to cover all FSM travel legs. Consistent with ADR-0013 Implementation Guidelines.
**Test Evidence**: Integration test at `tests/integration/logistics/route_path_integration_test.gd` (10 test functions)
**Code Review**: Skipped (Lean mode)

