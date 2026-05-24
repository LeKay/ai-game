# Story 003: Building Placement Validation Gate

> **Epic**: Grid/Map System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/grid-map-system.md`
**Requirement**: `TR-grid-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: Grid Map Data Model and TileMapLayer Rendering
**ADR Decision Summary**: `validate_placement(tile, building_type) -> PlacementResult` is the single gate for all placement decisions. It checks: bounds → impassable → existing building → resource clearability. Never mutates state. `place_building` atomically validates then writes. No consuming system implements its own placement logic.

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: No post-cutoff engine APIs used in this story (pure GDScript data manipulation). The `assert()` pattern for internal contracts is stable. `PackedScene` instantiation for buildings happens in the consuming Building System, not GridMap — GridMap only updates `_buildings` array data.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Any system implementing its own placement check outside `validate_placement`; `TileMapLayer.get_cell()` from gameplay code
- Guardrail: `place_building` must be atomic — validate and write in a single call with no gap

---

## Acceptance Criteria

*From GDD `design/gdd/grid-map-system.md`, scoped to this story:*

- [ ] **AC-3**: Given a tile at (5, 5) with TREE type and `clearable = true`, when a building is placed on this tile, then ResourceLayer[5][5] becomes null and BuildingLayer[5][5] is set to the building_id
- [ ] **AC-5**: Given an EMPTY tile at (10, 10) with no building, when `validate_placement(10, 10, "lumber_yard")` is called, then result is `SUCCESS`
- [ ] **AC-6**: Given an IMPASSABLE tile at (2, 2), when `validate_placement(2, 2, "lumber_yard")` is called, then result is `BLOCKED_BY_IMPASSABLE`
- [ ] **AC-7**: Given a tile at (7, 3) with a building already placed, when `validate_placement(7, 3, "lumber_yard")` is called, then result is `BLOCKED_BY_BUILDING`
- [ ] **AC-8**: Given coordinates (-1, 5), when `validate_placement(-1, 5, "lumber_yard")` is called, then result is `BLOCKED_BY_BOUNDS`
- [ ] **AC-9**: Given a STONE resource tile at (5, 5), when `validate_placement(5, 5, "lumber_yard")` is called, then result is `BLOCKED_BY_RESOURCE_TILE`
- [ ] **AC-10**: Given a TREE resource tile (clearable = true) at (5, 5) with no building, when `validate_placement(5, 5, "lumber_yard")` is called, then result is `SUCCESS`
- [ ] **AC-11**: Given `validate_placement` returns SUCCESS, when `place_building(10, 10, "lumber_yard")` is called, then `get_building(Vector2i(10, 10))` returns `"lumber_yard"`
- [ ] **AC-19**: Given a TREE resource tile at (x, y) with `clearable = true`, when `place_building(x, y, "lumber_yard")` succeeds, then `get_resource(Vector2i(x, y))` returns null
- [ ] **AC-20**: Given a STONE resource tile at (x, y) with `clearable = false`, when `validate_placement(x, y, "lumber_yard")` is called, then result is `BLOCKED_BY_RESOURCE_TILE`
- [ ] **AC-21**: Given a BERRY resource tile at (x, y) with `clearable = true`, when `place_building(x, y, building)` is called, then `get_resource(Vector2i(x, y))` returns null

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

```gdscript
func validate_placement(tile: Vector2i, building_type: String) -> PlacementResult:
    if not is_in_bounds(tile):
        return PlacementResult.BLOCKED_BY_BOUNDS
    if get_terrain(tile) == TileType.IMPASSABLE:
        return PlacementResult.BLOCKED_BY_IMPASSABLE
    if get_building(tile) != null:
        return PlacementResult.BLOCKED_BY_BUILDING
    var res := get_resource(tile)
    if res != null and not res.clearable:
        return PlacementResult.BLOCKED_BY_RESOURCE_TILE
    return PlacementResult.SUCCESS

func place_building(tile: Vector2i, building_id: String) -> PlacementResult:
    var result := validate_placement(tile, building_id)
    if result != PlacementResult.SUCCESS:
        return result
    # Atomically: update BuildingLayer, clear resource if clearable
    _buildings[tile.x][tile.y] = building_id
    var res := get_resource(tile)
    if res != null and res.clearable:
        _resources[tile.x][tile.y] = null
    return PlacementResult.SUCCESS

func remove_building(tile: Vector2i) -> bool:
    if not is_in_bounds(tile):
        return false
    if get_building(tile) == null:
        return false
    _buildings[tile.x][tile.y] = null
    return true
```

**Atomic validate-then-place**: `place_building` calls `validate_placement` internally as the final check. There is no "commit" phase separate from validation — they happen in one method call. This prevents race conditions where the tile changes between validate and place.

**Resource clearing**: When a building is placed on a clearable resource tile, `_resources[tile.x][tile.y]` is set to null. The resource is permanently removed — no recovery. TileMapLayer sync (clearing the resource cell visual) is handled by Story 006.

**Stone is not clearable** (`clearable = false`): `validate_placement` returns `BLOCKED_BY_RESOURCE_TILE` even though stone is a valid resource tile. The clearable flag on `ResourceTileData` is the single authority.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Data model, enums, read API
- Story 002: Generation populates the tiles that placement validates against
- Story 006: Calling `TileMapLayer.set_cell()` to visually clear resource cells after placement

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-5**: SUCCESS on empty tile
  - Given: GridMap with tile (10, 10) = EMPTY, no resource, no building
  - When: `validate_placement(Vector2i(10, 10), "lumber_yard")`
  - Then: returns `PlacementResult.SUCCESS`

- **AC-6**: BLOCKED_BY_IMPASSABLE
  - Given: GridMap with tile (2, 2) = IMPASSABLE
  - When: `validate_placement(Vector2i(2, 2), "lumber_yard")`
  - Then: returns `PlacementResult.BLOCKED_BY_IMPASSABLE`

- **AC-7**: BLOCKED_BY_BUILDING
  - Given: GridMap with tile (7, 3) having `_buildings[7][3] = "house"`
  - When: `validate_placement(Vector2i(7, 3), "lumber_yard")`
  - Then: returns `PlacementResult.BLOCKED_BY_BUILDING`

- **AC-8**: BLOCKED_BY_BOUNDS
  - Given: GridMap (GRID_SIZE = 30)
  - When: `validate_placement(Vector2i(-1, 5), "lumber_yard")`
  - Then: returns `PlacementResult.BLOCKED_BY_BOUNDS`
  - Edge cases: (30, 0), (0, 30), (30, 30) all return BLOCKED_BY_BOUNDS; (29, 29) returns SUCCESS if empty

- **AC-9 / AC-20**: BLOCKED_BY_RESOURCE_TILE for non-clearable stone
  - Given: GridMap with tile (5, 5) having resource `{resource_id: "stone", clearable: false}`
  - When: `validate_placement(Vector2i(5, 5), "lumber_yard")`
  - Then: returns `PlacementResult.BLOCKED_BY_RESOURCE_TILE`

- **AC-10**: SUCCESS on clearable tree tile
  - Given: GridMap with tile (5, 5) having resource `{resource_id: "wood", clearable: true}`, no building
  - When: `validate_placement(Vector2i(5, 5), "lumber_yard")`
  - Then: returns `PlacementResult.SUCCESS`

- **AC-3 / AC-11 / AC-19**: place_building — updates BuildingLayer and clears clearable resource
  - Given: GridMap with tile (5, 5) = TREE, `{resource_id: "wood", clearable: true}`, no building
  - When: `place_building(Vector2i(5, 5), "lumber_yard")`
  - Then: returns SUCCESS; `get_building(Vector2i(5, 5))` == `"lumber_yard"`; `get_resource(Vector2i(5, 5))` == null

- **AC-21**: place_building — clears clearable berry tile
  - Given: tile (3, 3) = BERRY, `{resource_id: "berry", clearable: true}`, no building
  - When: `place_building(Vector2i(3, 3), "farm")`
  - Then: `get_resource(Vector2i(3, 3))` == null

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/grid/grid_placement_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (GridMap class, arrays, enums, and read API must exist)
- Unlocks: Building System stories (which call `validate_placement` and `place_building`)
