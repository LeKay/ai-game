# Story 001: Grid Data Model and Core Read API

> **Epic**: Grid/Map System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/grid-map-system.md`
**Requirement**: `TR-grid-001`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: Grid Map Data Model and TileMapLayer Rendering
**ADR Decision Summary**: GridMap is a `Node` (not Autoload) owning three 30×30 data arrays — TerrainLayer (write-once), ResourceLayer (mutable), BuildingLayer (mutable). TileMapLayer nodes are pure rendering targets. All gameplay reads go through GridMap methods; `TileMapLayer.get_cell()` is never called from gameplay code.

**Engine**: Godot 4.6 | **Risk**: HIGH — TileMapLayer introduced in 4.3; LLM training covers ~4.3
**Engine Notes**: All read APIs (`Array`, `Vector2i`, `Node`) are stable. The `TerrainCell`, `ResourceCell`, `BuildingCell` inner classes use GDScript class_name — verify `inner class` pattern works as expected in Godot 4.6 before use. `harvest_resource` mutates ResourceLayer; TerrainLayer must assert immutability after generation.

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: `TileMapLayer.get_cell()` from any gameplay code; hardcoded resource definitions inline in GridMap
- Guardrail: < 0.1ms for 50 `get_tile_view()` calls per frame (AC #27)

---

## Acceptance Criteria

*From GDD `design/gdd/grid-map-system.md`, scoped to this story:*

- [ ] **AC-1**: Given the grid is initialized with GRID_SIZE = 30, when `get_terrain(15, 15)` is called, then the returned value is one of `TileType` enum values (`EMPTY`, `TREE`, `STONE`, `BERRY`, `GRASS`, `IMPASSABLE`)
- [ ] **AC-27** *(Performance)*: Given 50 `get_tile_view()` calls per frame at 60fps, then grid query overhead is < 0.1ms total

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

Create `src/systems/grid_map.gd` as `class_name GridMap extends Node`:

```gdscript
class_name GridMap extends Node

const GRID_SIZE: int = 30
const TILE_SIZE: int = 48  # pixels

enum TileType { EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE }

enum PlacementResult {
    SUCCESS,
    BLOCKED_BY_BOUNDS,
    BLOCKED_BY_IMPASSABLE,
    BLOCKED_BY_BUILDING,
    BLOCKED_BY_RESOURCE_TILE
}

class ResourceTileData:
    var resource_id: StringName
    var clearable: bool

class TileView:
    var terrain: TileType
    var resource: ResourceTileData
    var building_id: String

var _terrain: Array[Array]   # Array[Array[TileType]]  30×30
var _resources: Array[Array] # Array[Array[ResourceTileData?]]  30×30
var _buildings: Array[Array] # Array[Array[String?]]  30×30
var _generation_done: bool = false
```

**Read API** (all bounds-checked; out-of-bounds raises `assert(false, "...")`):
- `get_terrain(tile: Vector2i) -> TileType`
- `get_resource(tile: Vector2i) -> ResourceTileData` (null if no resource)
- `get_building(tile: Vector2i) -> String` (null if no building)
- `get_tile_view(tile: Vector2i) -> TileView` — composite read-only snapshot
- `is_passable(tile: Vector2i) -> bool` — false only for IMPASSABLE
- `is_in_bounds(tile: Vector2i) -> bool` — does NOT raise assertion; safe for callers to check before querying

**Resource mutation:**
- `harvest_resource(tile: Vector2i, amount: int) -> int` — if no resource at tile, return 0 with no mutation. Since resources are Anno-style spatial anchors (present or cleared, no quantity), `harvest_resource` clears the resource and returns 1 (a resource was there) or 0 (no resource). Do not track quantities.

**TerrainLayer immutability**: After `_generation_done = true`, any code path attempting to write `_terrain` raises `assert(false, "TerrainLayer is immutable after generation")`.

**Data ownership invariance**: GridMap arrays are authoritative. TileMapLayer calls `set_cell()` to sync rendering but GridMap never calls `get_cell()` to read back. This is an enforced pattern; see Out of Scope.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `generate(seed)` — procedural generation fills the arrays; in this story, initialize all arrays to default values only (EMPTY, null, null)
- Story 003: `validate_placement`, `place_building`, `remove_building`
- Story 004: `world_to_tile`, `tile_to_world` coordinate conversion
- Story 005: `manhattan_dist`, `euclidean_dist`, `get_tiles_in_radius`, `find_nearest`
- Story 006: TileMapLayer scene wiring and rendering

*Stub generation and placement methods as `pass` or empty — do not implement their logic in this story.*

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Grid initializes and returns valid TileType
  - Given: GridMap is initialized with GRID_SIZE = 30, all terrain cells default to EMPTY
  - When: `get_terrain(Vector2i(15, 15))` is called
  - Then: result is `TileType.EMPTY` (valid enum value)
  - Edge cases: `get_terrain(Vector2i(0, 0))` and `get_terrain(Vector2i(29, 29))` both return valid TileType; calling `get_terrain(Vector2i(-1, 0))` triggers assert

- **AC-27**: 50 get_tile_view calls complete within 0.1ms
  - Given: GridMap is initialized (arrays allocated, no generation needed)
  - When: 50 calls to `get_tile_view(Vector2i(15, 15))` are made in a tight loop
  - Then: total wall-clock time < 0.1ms (measure via `Time.get_ticks_usec()`)
  - Edge cases: calls at corner tiles (0,0), (29,29), and center (15,15)

- **harvest_resource — no resource tile**:
  - Given: tile at (10, 10) has no resource (null ResourceTileData)
  - When: `harvest_resource(Vector2i(10, 10), 1)` is called
  - Then: returns 0, ResourceLayer[10][10] remains null

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/grid/grid_data_model_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None (this is the first story; creates the GridMap class skeleton)
- Unlocks: Story 002 (Procedural Generation — fills the arrays created here), Story 003 (Placement Validation — uses enums and read API), Story 004 (Coordinate Conversion — uses TILE_SIZE), Story 005 (Spatial Queries — uses read API), Story 006 (TileMapLayer Rendering — needs GridMap node to wire to)
