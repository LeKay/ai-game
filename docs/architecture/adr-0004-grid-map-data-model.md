# ADR-0004: Grid Map Data Model and TileMapLayer Rendering

## Status

Accepted

## Date

2026-05-13

## Last Verified

2026-05-13

## Decision Makers

Technical Director, Creative Director (design decisions), Godot GDScript Specialist (engine API)

## Summary

Defines the GridMap system as the single source of truth for world state: a fixed 30×30 three-layer data model (TerrainLayer, ResourceLayer, BuildingLayer) rendered by TileMapLayer nodes. Placement validation flows through a single `validate_placement` gate. Perlin noise drives procedural generation. Coordinate conversion bridges tile-space logic and pixel-space rendering.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Rendering |
| **Knowledge Risk** | HIGH — `TileMapLayer` introduced in 4.3, project targets 4.6; LLM training data covers ~4.3. `FastNoise` (the class suggested by pre-4.x docs) does not exist in Godot 4.x; the correct class is `FastNoiseLite`. Confirm `get_noise_2d` return range and any property changes. |
| **References Consulted** | `docs/engine-reference/godot/breaking-changes.md` (4.2→4.3: TileMap→TileMapLayer), `docs/engine-reference/godot/deprecated-apis.md` (TileMap→TileMapLayer), `docs/engine-reference/godot/VERSION.md` (4.5→4.6 TileMapLayer scene tile rotation), `docs/architecture/architecture.md` (Module Ownership, API Boundaries) |
| **Post-Cutoff APIs Used** | `TileMapLayer` (4.3+), `TileMapLayer.set_cell()` (4.3+), `TileSet` with `tile_size` (4.3+), `YSort` via `Node2D.y_sort_enabled` (4.0+), `FastNoiseLite` (Godot 4.x noise class) |
| **Verification Required** | Confirm `TileMapLayer.set_cell()` batch call pattern works without per-tile overhead. Verify `Node2D.y_sort_enabled` property (not YSort node) works for building/character depth sorting. Test `FastNoiseLite.get_noise_2d()` returns `[-1.0, 1.0]` range as documented. Confirm 4.6 behavior: scene-level tile rotation on TileMapLayer does not interfere with our tile-based data model. |

> **Note**: TileMap→TileMapLayer deprecation is HIGH risk because using `TileMap` would cause runtime warnings and incompatible data layouts. The ADR explicitly bans `TileMap`.

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (ResourceRegistry — Grid's ResourceLayer stores resource_id references to the registry) |
| **Enables** | ADR-0008 (Building placement validation gate), ADR-0009 (NPC Manhattan movement on grid) |
| **Blocks** | All GridMap stories, Building System stories (require `validate_placement`), Camera System stories (require coordinate conversion), Logistics System stories (require distance functions) |
| **Ordering Note** | ADR-0001 (TickSystem), ADR-0002 (ResourceRegistry), ADR-0003 (InputContext) should be accepted before this ADR, since GridMap consumes their APIs at startup. |

## Context

### Problem Statement

The game world needs a spatial foundation — a deterministic tile grid that all systems query for placement validation, distance calculations, resource discovery, and rendering. Without a central data model, every system would implement its own coordinate and validation logic, creating inconsistencies that are impossible to debug in a top-down strategy game.

### Current State

No GridMap ADR exists. The architecture document defines the module ownership and API boundaries, but no detailed ADR exists to guide implementation. The TR registry lists six technical requirements (TR-grid-001 through TR-grid-006) that must all be satisfied.

### Constraints

- **Engine**: Godot 4.6 — `TileMap` is deprecated since 4.3; must use `TileMapLayer` (one node per visual layer).
- **Grid size**: 30×30 for Vertical Slice, 50×50 for MVP (separate instantiation, no runtime resizing).
- **Tile size**: 64×64 pixels — fits on 1920×1080 with UI overhead (1920×1920 map viewport at 30 tiles).
- **Determinism**: Same seed must produce identical maps (required for save/load consistency).
- **Data ownership**: GridMap owns all world state; TileMapLayer is a pure rendering target with no independent state.
- **Read-back prohibition**: Gameplay code must NEVER call `TileMapLayer.get_cell()` — data reads only from GridMap.
- **Depth ordering**: Game objects must use `Node2D.y_sort_enabled` (not legacy `YSort` node, deprecated since 4.0).
- **Resource IDs**: Grid references resource types by StringName from ResourceRegistry — no inline resource definitions.
- **Perlin noise**: Godot 4.x uses `FastNoiseLite` with `noise_type = FastNoiseLite.TYPE_PERLIN`. `FastNoise` does not exist as a standalone class in Godot 4.x — `FastNoiseLite` is the correct API. Configuration: two instances (elevation: FBM, 4 octaves, frequency 0.05; moisture: FBM, 3 octaves, frequency 0.08).

### Requirements

- TR-grid-001: 30×30 tile grid, 3-layer data model (Terrain/Resource/Building)
- TR-grid-002: TileMapLayer rendering (TileMap deprecated — must not use)
- TR-grid-003: Perlin noise procedural terrain generation at world init
- TR-grid-004: validate_placement gate (checks all 3 layers before any placement)
- TR-grid-005: Manhattan + Euclidean distance functions
- TR-grid-006: World-space to tile-coordinate conversion

## Decision

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  MapRoot (Node2D)                        │
│                                                  y_sort_enabled=true                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  TileMapLayer: TerrainLayer (visual only)        │  │
│  │  TileMapLayer: ResourceOverlay (visual only)     │  │
│  │  TileMapLayer: BuildingSlots (visual only)       │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Grid (Node — pure data, no rendering)            │  │
│  │                                                   │  │
│  │  _terrain: Array[Array[TerrainCell]]  30×30      │  │
│  │  _resources: Array[Array[ResourceCell]] 30×30    │  │
│  │  _buildings: Array[Array[BuildingCell?]] 30×30   │  │
│  │                                                   │  │
│  │  ┌─ validate_placement(pos, type) -> enum         │  │
│  │  ├─ place_building(pos, type) -> enum             │  │
│  │  ├─ remove_building(pos) -> bool                  │  │
│  │  ├─ harvest_resource(pos, amount) -> int          │  │
│  │  ├─ get_terrain(pos) -> TileType                  │  │
│  │  ├─ get_resources(pos) -> Array[ResourceTileData]  │  │
│  │  ├─ get_building(pos) -> String?                  │  │
│  │  ├─ get_tile_view(pos) -> TileView                │  │
│  │  ├─ world_to_tile(world_pos) -> Vector2i          │  │
│  │  ├─ tile_to_world(tile_pos) -> Vector2            │  │
│  │  ├─ manhattan_dist(a, b) -> int                   │  │
│  │  ├─ euclidean_dist(a, b) -> float                 │  │
│  │  └─ get_tiles_in_radius(cx, cy, radius) -> arr    │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘

Data flow (unidirectional):
  Grid (authoritative data) ──set_cell()──► TileMapLayer (rendering target only)
  Gameplay code ──grid.get_tile()──► Grid (NEVER calls TileMapLayer.get_cell())
```

### Key Interfaces

```gdscript
class_name GridMap extends Node

const GRID_SIZE: int = 30
const TILE_SIZE: int = 64  # pixels

enum TileType { EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE }

enum PlacementResult {
	SUCCESS,
	BLOCKED_BY_BOUNDS,
	BLOCKED_BY_IMPASSABLE,
	BLOCKED_BY_BUILDING,
	BLOCKED_BY_RESOURCE_TILE
}

# --- Generation (called once during _ready()) ---

func generate(seed: int) -> void
	# Steps: Perlin sampling → threshold segmentation → smoothing (2 iterations) →
	# cluster cleanup (min 3) → minimum count verification (max 5 seed attempts)

# --- Placement validation (single gate) ---

func validate_placement(tile: Vector2i, building_type: BuildingType) -> PlacementResult
	# Checks: bounds → impassable → building → resource clearability
	# Never mutates state — read-only validation.

func place_building(tile: Vector2i, building_type: BuildingType) -> PlacementResult
	# Atomically: calls validate_placement → if SUCCESS, updates BuildingLayer →
	# clears ResourceLayer if tile had a clearable resource.

func remove_building(tile: Vector2i) -> bool

func harvest_resource(tile: Vector2i, amount: int) -> int

# --- Reads ---

func get_terrain(tile: Vector2i) -> TileType
func get_resources(tile: Vector2i) -> Array[ResourceTileData]  # empty = no resource
func get_building(tile: Vector2i) -> String?
func get_tile_view(tile: Vector2i) -> TileView  # composite read-only snapshot

func is_in_bounds(tile: Vector2i) -> bool

# --- Coordinate conversion ---

func world_to_tile(world_pos: Vector2) -> Vector2i
	# tile = floor(world_pos / TILE_SIZE)

func tile_to_world(tile: Vector2i) -> Vector2
	# center = tile * TILE_SIZE + TILE_SIZE / 2

# --- Distance ---

func manhattan_dist(a: Vector2i, b: Vector2i) -> int
	# |x1 - x2| + |y1 - y2|

func euclidean_dist(a: Vector2i, b: Vector2i) -> float
	# sqrt((x1-x2)^2 + (y1-y2)^2)

func distance_between(a: Vector2i, b: Vector2i, metric: DistanceMetric) -> float
	# Unified distance dispatch — consumed by NPCSystem and BuildingSystem.
	# DistanceMetric is an enum: MANHATTAN, EUCLIDEAN.
	# MANHATTAN: returns manhattan_dist(a, b) as float
	# EUCLIDEAN: returns euclidean_dist(a, b)
	# This method exists so consumers do not need to know which
	# distance function is available — they just specify the metric.

# --- Spatial queries ---

func get_tiles_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]
	# Square bounding box, clipped to grid bounds. Callers needing circular
	# radius must post-filter by euclidean_dist.

func get_neighbors(tile: Vector2i, diagonals: bool = false) -> Array[Vector2i]

func find_nearest(tile: Vector2i, resource_id: StringName, max_radius: int) -> Vector2i?

func find_tiles_by_predicate(predicate: Callable) -> Array[Vector2i]

# Serialization

func serialize() -> Dictionary
func deserialize(data: Dictionary) -> void
```

### Implementation Guidelines

1. **TileMapLayer over TileMap**: Use one `TileMapLayer` node per visual layer (terrain, resource overlay, building slots). Each has `TileSet` with `tile_size = Vector2i(64, 64)`. NEVER instantiate or reference a `TileMap` node.

2. **Data ownership invariance**: The Grid's 3 layer arrays are the sole truth. TileMapLayer cells are derived from Grid data via `set_cell()` calls — always in batch after generation or after a resource tile is cleared. Gameplay code reads Grid methods only.

3. **Y-sort depth ordering**: All game objects that need proper depth ordering (buildings, characters, items) must be children of a `Node2D` with `y_sort_enabled = true`. Do NOT use the legacy `YSort` node (deprecated since 4.0).

4. **Perlin noise generation**: Use `FastNoiseLite` (Godot 4.x) — `FastNoise` does not exist as a standalone class in Godot 4. Set `noise_type = FastNoiseLite.TYPE_PERLIN` and `fractal_type = FastNoiseLite.FRACTAL_FBM`. Configure two instances — elevation (`fractal_octaves = 4`, `frequency = 0.05`) and moisture (`fractal_octaves = 3`, `frequency = 0.08`). Normalize output from `[-1.0, 1.0]` to `[0.0, 1.0]` via `(value + 1.0) / 2.0`.

5. **validate_placement is the single gate**: All placement code — Building System, HUD ghost preview, Camera hover — calls this one function. No system implements its own placement logic. The function returns an enum with specific blocking reasons.

6. **Coordinate conversion**: Tile-to-world returns tile center (`tile * TILE_SIZE + TILE_SIZE / 2`). World-to-tile uses `floor()`. Mouse-to-tile goes through: `screen_pos → world_pos (accounting for camera offset and zoom) → tile`.

7. **Manhattan vs Euclidean**: Manhattan is the default and primary metric (grid-based NPC movement). Euclidean is available for Anno-style "resource in radius" checks where circular proximity matters.

8. **get_tiles_in_radius returns square bounding box**: This is faster for initial filtering. Callers requiring true circular proximity must post-filter by `euclidean_dist(center, tile) <= radius`. Out-of-bounds tiles are silently omitted.

## Alternatives Considered

### Alternative 1: Single-layer grid with composite tile entries

- **Description**: One 2D array where each cell is a struct containing terrain, resource, and building data combined.
- **Pros**: Simpler data structure; fewer array operations.
- **Cons**: Updating terrain type requires recreating the entire composite struct; layer independence (GDD requirement) is lost; mutations cascade across layers.
- **Estimated Effort**: Same as chosen approach.
- **Rejection Reason**: The GDD explicitly requires independent mutability per layer (TerrainLayer is write-once, ResourceLayer is mutable, BuildingLayer is mutable with different write access). Composite entries would force all layers to share the same mutability rules.

### Alternative 2: TileMap (deprecated) for rendering

- **Description**: Use Godot 4.x `TileMap` node (multi-layer, single node) for rendering instead of `TileMapLayer`.
- **Pros**: Familiar to developers who worked with Godot 3.x or early 4.x; single node manages all layers.
- **Cons**: `TileMap` is deprecated since Godot 4.3; does not match Godot 4.6 rendering model; future upgrades may remove `TileMap` entirely; the Architecture doc explicitly flags this as HIGH risk.
- **Estimated Effort**: Less initial work (one node vs three), but migration cost later.
- **Rejection Reason**: TR-grid-002 mandates `TileMapLayer`. Using `TileMap` would violate the requirement and create a debt that must be paid before Vertical Slice ships.

### Alternative 3: Third-party GDExtension noise library

- **Description**: Use a GDExtension noise library instead of Godot's built-in `FastNoiseLite`.
- **Pros**: More configurable noise types (Voronoi, domain warping, custom implementations).
- **Cons**: Adds an external dependency; unnecessary complexity for VS scope; `FastNoiseLite.TYPE_PERLIN` with FBM provides sufficient quality.
- **Estimated Effort**: 1–2 hours additional for library integration and testing.
- **Rejection Reason**: Built-in `FastNoiseLite` with `TYPE_PERLIN` is adequate for the required terrain quality. No external dependency needed.

## Consequences

### Positive

- Single source of truth eliminates inconsistencies between systems querying grid data.
- `validate_placement` as a single gate prevents placement logic drift across consuming systems.
- Layer independence means terrain generation, resource placement, and building placement can evolve independently.
- TileMapLayer (Godot 4.6 native) provides per-layer rendering with independent TileSets — the correct model for the 3-layer GDD.
- Coordinate conversion functions are deterministic and bidirectional (tile → world → tile round-trips correctly).

### Negative

- TileMapLayer requires 3 node instances in the scene tree (vs 1 for `TileMap`), adding minor scene hierarchy depth.
- Perlin noise tuning requires iteration — default parameters (scale 9.0, 4 octaves) produce reasonable clusters but may need adjustment for the specific art style.
- Square bounding box in `get_tiles_in_radius` means callers needing circular queries must add an extra filter step — a small cognitive overhead.

### Neutral

- 30×30 grid is fixed at instantiation — changing to 50×50 requires creating a new Grid instance, not resizing.
- Resource tiles are permanently removed when buildings are placed — no regeneration or replenishment.
- TerrainLayer becomes immutable after `_ready()` — enforced by assertion, not by data structure.

### Post-acceptance amendments (2026-05-31)

- **TILE_SIZE corrected to 64**: ADR was authored with 48px; implementation verified 64px is the correct value used across `WorldGrid`, `CameraController`, `MapRoot`, and all tests. All coordinate conversion values updated accordingly.
- **FastNoiseLite replaces FastNoise**: ADR incorrectly specified `FastNoise` (a Godot 3.x / pre-release class name). `FastNoise` does not exist in Godot 4.x — `FastNoiseLite` is the correct class. Implementation already used `FastNoiseLite` correctly. ADR updated to match.

### Post-acceptance amendments (2026-05-28)

- **Resource data model broadened**: `_resources[x][y]` stores `Array[ResourceTileData]` instead of `ResourceTileData|null`. `get_resource()` renamed to `get_resources()` returning `Array[ResourceTileData]` (empty = no resource). `TileView.resource` renamed to `TileView.resources: Array`. Enables multiple resources per tile without changing the three-layer architecture.
- **ResourceOverlay TileMapLayer unused for rendering**: Resources are now displayed as runtime-spawned Sprite2D badge nodes in a `ResourceBadges` Node2D container (z_index 1) rather than via `ResourceOverlay.set_cell()`. `ResourceOverlay` remains in the scene tree with no TileSet assigned. The invariant that TileMapLayer is a pure rendering target (not queried by gameplay code) is unchanged.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| `TileMapLayer` API differs from 4.3 documentation | MEDIUM | HIGH | Verify `set_cell()`, `get_cell()`, `TileSet.tile_size` against Godot 4.6 docs before implementation. The breaking-changes doc notes 4.6 added scene-level tile rotation to TileMapLayer — confirm this doesn't affect our coordinate model. |
| Perlin noise produces maps with insufficient resources | LOW | HIGH | GDD includes 5-attempt regeneration with force-fix fallback. Verified by acceptance criteria #4 and #22. |
| Y-sort conflicts with TileMapLayer rendering order | LOW | MEDIUM | TileMapLayer renders at a fixed layer depth; game objects as children of y_sort_enabled Node2D are sorted within their own depth layer. Test with actual scenes. |
| Coordinate conversion off-by-one at tile edges | LOW | MEDIUM | `floor()` in world_to_tile handles this correctly; acceptance criteria #12–14 verify exact values. Unit test with boundary tiles (0,0) and (29,29). |
| `get_tiles_in_radius` square-box behavior confusing to callers | MEDIUM | LOW | Document the square-box pattern in the GridMap class docstring. Provide `get_tiles_in_circular_radius()` as a convenience wrapper that calls the square method then filters. |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| Grid query (get_tile_view) | — | < 0.002 ms | < 0.01 ms |
| Grid query (get_tiles_in_radius, 30×30) | — | < 0.01 ms | < 1 ms (AC #26) |
| Map generation (Perlin noise, 900 tiles) | — | ~5–20 ms (one-time) | N/A — startup only |
| TileMapLayer batch set_cell (900 tiles) | — | ~2–5 ms (one-time) | N/A — startup only |
| Memory (3 × 30 × 30 layer arrays) | — | ~54 KB | < 1 MB |

The grid query overhead (AC #27) targets < 0.1ms total for 50 calls per frame at 60fps — well within budget for 30×30 grid sizes.

## Migration Plan

This is a new ADR — no migration from existing code. Implementation steps:

1. Create `GridMap` class with 3 layer arrays (TerrainCell, ResourceCell, BuildingCell structs) — unit test data model invariants.
2. Implement `generate(seed)` with Perlin noise, threshold segmentation, smoothing, cluster cleanup, and minimum count verification — run acceptance criteria #1–#4.
3. Implement `validate_placement` and `place_building` with all 5 PlacementResult outcomes — run acceptance criteria #5–#11.
4. Implement coordinate conversion and distance functions — run acceptance criteria #12–#18.
5. Wire TileMapLayer nodes to GridMap in `MapRoot.tscn` scene — verify rendering matches grid data.
6. Implement Y-sort for game objects under `Node2D` with `y_sort_enabled = true`.
7. Add serialization/deserialization — verify save/load round-trip with acceptance criteria #2.

**Rollback plan**: GridMap is an isolated system. If the data model proves flawed, delete `GridMap.gd` and rewrite. TileMapLayer scene nodes are standard Godot nodes — removing them has no side effects. No other system is implemented yet, so rollback has zero downstream impact.

## Validation Criteria

- [ ] Grid initializes with `GRID_SIZE = 30` and `get_tile_view(15, 15)` returns a valid `TileView` with a `TileType` enum value (AC #1)
- [ ] Same seed (42) produces tile-for-tile identical maps across regenerations (AC #2)
- [ ] `validate_placement` returns correct `PlacementResult` for all 5 blocking conditions: SUCCESS, BLOCKED_BY_BOUNDS, BLOCKED_BY_IMPASSABLE, BLOCKED_BY_BUILDING, BLOCKED_BY_RESOURCE_TILE (AC #5–#10)
- [ ] Building placement updates BuildingLayer and clears clearable resources (AC #3, #11)
- [ ] Coordinate conversion: tile (5,12) → pixel center (352,800) are exact (AC #12–14) — `5×64+32=352`, `12×64+32=800`
- [ ] `get_tiles_in_radius(15, 15, 1)` returns exactly 9 tiles (AC #15)
- [ ] Manhattan distance between (0,0) and (5,5) = 10; Euclidean between (0,0) and (3,4) = 5.0 ± 0.001 (AC #16–17)
- [ ] `find_nearest` returns closest tile by Manhattan distance (AC #18)
- [ ] 50 `get_tile_view()` calls complete in < 0.1ms total at 60fps (AC #27)
- [ ] No gameplay code references `TileMapLayer.get_cell()` — verified by code review
- [ ] TerrainLayer is immutable after generation — verified by assertion test

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/grid-map-system.md` | GridMap | TR-grid-001: 30×30 tile grid, 3-layer data model (Terrain/Resource/Building) | Three independent 2D arrays (`_terrain`, `_resources`, `_buildings`) with independent mutability rules defined in the GridMap class interface. |
| `design/gdd/grid-map-system.md` | GridMap | TR-grid-002: TileMapLayer rendering (TileMap deprecated — must not use) | Architecture explicitly bans `TileMap`. Three `TileMapLayer` nodes defined: TerrainLayer, ResourceOverlay, BuildingSlots. Each with `TileSet.tile_size = Vector2i(48, 48)`. |
| `design/gdd/grid-map-system.md` | GridMap | TR-grid-003: Perlin noise procedural terrain generation at world init | `generate(seed: int)` implements 5-step pipeline: Perlin sampling (elevation + moisture) → threshold segmentation → smoothing (2 iterations) → cluster cleanup → minimum count verification. |
| `design/gdd/grid-map-system.md` | GridMap | TR-grid-004: validate_placement gate (checks all 3 layers before any placement) | Single `validate_placement(tile, building_type) -> PlacementResult` function checks: bounds → impassable → existing building → resource clearability. Returns enum with specific blocking reasons. |
| `design/gdd/grid-map-system.md` | GridMap | TR-grid-005: Manhattan + Euclidean distance functions | `manhattan_dist(a, b) -> int` and `euclidean_dist(a, b) -> float` defined as public methods. Manhattan is primary (NPC movement); Euclidean available for Anno-style radius checks. |
| `design/gdd/grid-map-system.md` | GridMap | TR-grid-006: World-space to tile-coordinate conversion | `world_to_tile(world_pos: Vector2) -> Vector2i` using `floor()` and `tile_to_world(tile_pos: Vector2i) -> Vector2` returning tile center. Mouse-to-tile conversion documented with camera offset and zoom. |

## Related

- **Depends on**: ADR-0002 (ResourceRegistry — Grid references resource types via StringName)
- **Enables**: ADR-0008 (Building placement), ADR-0009 (NPC Manhattan movement)
- **Related**: `design/gdd/grid-map-system.md` (GDD — detailed rules and formulas)
- **Architecture**: `docs/architecture/architecture.md` Module Ownership (GridMap section, line 205–206) and API Boundaries (GridMap section, line 465–490)
