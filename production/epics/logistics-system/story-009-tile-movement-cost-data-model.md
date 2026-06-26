# Story 009: Tile Movement Cost Data Model

> **Epic**: Logistics System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/logistics-system.md`
**Requirement**: `TR-logistics-015`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0013: Tile-Weighted Pathfinding for Logistics Routes
**ADR Decision Summary**: GridMap gains two new query methods — `get_tile_movement_cost(pos)` and `is_tile_passable(pos)` — resolved by priority-ordered layer checks (Building > Resource > Terrain). Resource tile costs are data-driven via `data/resources.json`. Buildings are always IMPASSABLE.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Post-cutoff APIs used: None — pure GDScript data model extension. `INF` float constant is stable since Godot 3.x.

**Control Manifest Rules (Feature Layer)**:
- Required: 4-stage building lifecycle (PLACE → CONSTRUCT → OPERATE → DEMOLISH)
- Required: Visual pool pattern — recycled scene templates, registry owns all state
- Forbidden: Never use TileMap for rendering — always TileMapLayer
- Forbidden: Never read tile state from TileMapLayer — always from GridMap data model

---

## Acceptance Criteria

*From ADR-0013, scoped to this story:*

- [ ] `GridMap.get_tile_movement_cost(pos: Vector2i) -> float` is implemented: returns `INF` if BuildingLayer is occupied at `pos`, `4.0` if ResourceLayer has a resource at `pos` with no building, `1.0` otherwise (open tile)
- [ ] `GridMap.is_tile_passable(pos: Vector2i) -> bool` is implemented: returns `false` if and only if `get_tile_movement_cost(pos) == INF`
- [ ] Each resource definition in `data/resources.json` has a new `"movement_cost"` float field; default is `4.0` for all existing resource types
- [ ] `GridMap.get_tile_movement_cost()` reads the `movement_cost` field from the resource registry when resolving ResourceLayer tiles (data-driven, not hardcoded)
- [ ] A tile with a building placed on it returns `INF` from `get_tile_movement_cost()` regardless of what is in the ResourceLayer at that position
- [ ] `GridMap` emits a new signal `terrain_changed(pos: Vector2i, layer: int)` when BuildingLayer or ResourceLayer state changes at any tile (building placed/demolished, resource added/removed)

---

## Implementation Notes

*Derived from ADR-0013:*

**Layer check priority** (implemented in `get_tile_movement_cost`):
```gdscript
func get_tile_movement_cost(pos: Vector2i) -> float:
    if _building_layer.get(pos) != null:
        return INF
    var resource_id: StringName = _resource_layer.get(pos, &"")
    if resource_id != &"":
        return ResourceRegistry.get_resource(resource_id).movement_cost
    return 1.0
```

**resources.json schema addition** — add `movement_cost` to each resource object:
```json
{
  "id": "wood",
  "movement_cost": 4.0,
  ...
}
```

**Road tiles (future, reserved)**: The `movement_cost` field on terrain tile definitions (not yet in `data/`) will allow road tiles to return `0.5`. No implementation needed now — the architecture already supports it because `get_tile_movement_cost` will naturally fall through to a future terrain-cost lookup. Document this as a TODO comment in the function body only.

**`terrain_changed` signal**: Emit from the two existing mutation points in GridMap:
- `place_building(pos)` / `demolish_building(pos)` → emit `terrain_changed(pos, BUILDING_LAYER)`
- `place_resource(pos)` / `remove_resource(pos)` → emit `terrain_changed(pos, RESOURCE_LAYER)`

Do not add new mutation paths — only wire the signal into existing ones.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 010]: The A* pathfinder that calls `get_tile_movement_cost` / `is_tile_passable`
- [Story 011]: Logistics route integration that replaces Manhattan distance with path cost
- [Story 012]: LogisticsSystem subscribing to `terrain_changed` to invalidate cached paths

---

## QA Test Cases

*Written by qa-lead at story creation.*

**Tile cost resolution:**

- **AC-1**: Open tile returns 1.0
  - Given: GridMap tile at (5, 5) has no building and no resource
  - When: `get_tile_movement_cost(Vector2i(5, 5))` is called
  - Then: Returns `1.0`
  - Edge cases: Out-of-bounds pos should not crash — return `INF` (treat as impassable wall)

- **AC-2**: Resource tile returns its `movement_cost`
  - Given: ResourceLayer at (3, 3) holds resource `"wood"`, `"wood"` has `movement_cost = 4.0`, no building at (3, 3)
  - When: `get_tile_movement_cost(Vector2i(3, 3))` is called
  - Then: Returns `4.0`

- **AC-3**: Building tile returns INF
  - Given: BuildingLayer at (7, 2) has a building placed
  - When: `get_tile_movement_cost(Vector2i(7, 2))` is called
  - Then: Returns `INF` (regardless of ResourceLayer state)

- **AC-4**: Building overrides resource
  - Given: Tile (4, 4) has both a building AND a resource in ResourceLayer
  - When: `get_tile_movement_cost(Vector2i(4, 4))` is called
  - Then: Returns `INF` (building takes priority)

- **AC-5**: `is_tile_passable` consistency
  - Given: Various tiles — open (1.0), resource (4.0), building (INF)
  - When: `is_tile_passable(pos)` is called for each
  - Then: open → `true`, resource → `true`, building → `false`

**`terrain_changed` signal:**

- **AC-6**: Signal emitted on building placement
  - Given: GridMap with empty tile at (2, 2)
  - When: `place_building(Vector2i(2, 2), building_id)` is called
  - Then: `terrain_changed(Vector2i(2, 2), BUILDING_LAYER)` is emitted exactly once

- **AC-7**: Signal emitted on building demolition
  - Given: Building at (2, 2)
  - When: `demolish_building(Vector2i(2, 2))` is called
  - Then: `terrain_changed(Vector2i(2, 2), BUILDING_LAYER)` is emitted exactly once

- **AC-8**: Signal emitted on resource removal
  - Given: Resource "wood" at (6, 6)
  - When: `remove_resource(Vector2i(6, 6))` is called
  - Then: `terrain_changed(Vector2i(6, 6), RESOURCE_LAYER)` is emitted exactly once

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/logistics/tile_movement_cost_test.gd` — must exist and pass

---

## Dependencies

- Depends on: ADR-0004 (GridMap data model — must have ResourceLayer and BuildingLayer already implemented)
- Unlocks: Story 010 (A* pathfinder calls `get_tile_movement_cost` / `is_tile_passable`)
- Unlocks: Story 012 (terrain_changed signal subscription)
