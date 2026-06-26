# Story 006: TileMapLayer Rendering Integration

> **Epic**: Grid/Map System
> **Status**: Complete
> **Layer**: Core
> **Type**: Visual/Feel
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/grid-map-system.md`
**Requirement**: `TR-grid-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: Grid Map Data Model and TileMapLayer Rendering
**ADR Decision Summary**: Four `TileMapLayer` nodes (BackgroundLayer, TerrainLayer, ResourceOverlay, BuildingSlots) are children of `MapRoot (Node2D)`. BackgroundLayer and TerrainLayer share one `TileSet`; ResourceOverlay has its own. After `WorldGrid.generate()`, a batch `set_cell()` pass populates all TileMapLayer cells: BackgroundLayer always receives EMPTY (grass); TerrainLayer receives terrain features only for non-EMPTY tiles. Data flows one way: Grid → TileMapLayer. `TileMap` (deprecated since 4.3) must not appear anywhere.

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: `TileMapLayer` introduced in 4.3; project targets 4.6. Verify `set_cell(coords, source_id, atlas_coords)` signature in 4.6 — the 4.6 migration guide notes that scene-level tile rotation was added to TileMapLayer; confirm this doesn't conflict with our atlas tile setup. `Node2D.y_sort_enabled = true` replaces the legacy `YSort` node (deprecated since 4.0). **Do not use the `YSort` node class.**

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Any `TileMap` node in `MapRoot.tscn`; any gameplay code calling `TileMapLayer.get_cell()`; legacy `YSort` node
- Guardrail: All 900 tiles must be set in one batch after generation — no per-frame tile writes

---

## Acceptance Criteria

*From GDD `design/gdd/grid-map-system.md`, scoped to this story:*

- [ ] **Rendering AC-A**: `MapRoot.tscn` scene contains exactly 4 `TileMapLayer` children (`BackgroundLayer`, `TerrainLayer`, `ResourceOverlay`, `BuildingSlots`) and zero `TileMap` nodes
- [ ] **Rendering AC-B**: After `WorldGrid.generate(42)`, every tile position in the 30×30 grid has a corresponding `set_cell()` call on `TerrainLayer` matching its `TileType`
- [ ] **Rendering AC-C**: `MapRoot` (or a `Node2D` parent of game objects) has `y_sort_enabled = true`; no `YSort` node appears in the scene tree
- [ ] **Rendering AC-D**: When `place_building(tile, building_id)` succeeds, `ResourceOverlay.set_cell(tile, -1, ...)` is called to clear the resource visual at that tile (if a clearable resource was there)
- [ ] **Rendering AC-E**: Terrain tiles use atlas tiles from a shared `TileSet` (single texture, atlas layout); each `TileType` maps to a distinct atlas coordinate

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

**Scene structure** (`MapRoot.tscn`):
```
MapRoot (Node2D)  ← y_sort_enabled = true
├── BackgroundLayer (TileMapLayer) — always renders EMPTY (grass) for every tile; shared TileSet with TerrainLayer
├── TerrainLayer (TileMapLayer)    — non-EMPTY terrain features (trees etc.); transparent PNGs composite over BackgroundLayer
├── ResourceOverlay (TileMapLayer) — resource indicator dots, own TileSet
├── BuildingSlots (TileMapLayer)   — 1×1 slot indicators (optional visual), TileSet unset
└── WorldGrid (Node)               — pure data node, no rendering
```

**TileSet setup**: Each `TileMapLayer` needs a `TileSet` resource with `tile_size = Vector2i(48, 48)`. For Vertical Slice, use placeholder colored rectangles per terrain type (art assets come later). Define atlas source with placeholder atlas texture.

**Batch set_cell after generation**: Add `_sync_tilemap()` method to `MapRoot` (or `WorldGrid`), called once after `generate()`:
```gdscript
func _sync_tilemap() -> void:
    for x in range(WorldGrid.GRID_SIZE):
        for y in range(WorldGrid.GRID_SIZE):
            var tile := Vector2i(x, y)
            var terrain_atlas := _terrain_type_to_atlas(grid.get_terrain(tile))
            terrain_layer.set_cell(tile, 0, terrain_atlas)
            var res := grid.get_resource(tile)
            if res:
                var res_atlas := _resource_id_to_atlas(res.resource_id)
                resource_overlay.set_cell(tile, 0, res_atlas)
```

**Resource clear on placement**: When `place_building` is called and a clearable resource is removed, call:
```gdscript
resource_overlay.set_cell(tile, -1, Vector2i(-1, -1))  # clears the cell
```
This call happens in `MapRoot` (which owns both WorldGrid and TileMapLayer nodes), not inside `WorldGrid` itself. WorldGrid updates data; MapRoot syncs rendering.

**Y-sort**: Set `MapRoot.y_sort_enabled = true` in the scene inspector or via `_ready()`. All game objects (buildings, characters, items) that need depth ordering must be children of `MapRoot` (or another `Node2D` with `y_sort_enabled`). TileMapLayer nodes render at fixed depth and are not Y-sorted.

**Verification before marking done**: Run the game, generate a map, and confirm:
1. All terrain types are visually distinct (colored placeholders are sufficient for VS)
2. Resource overlay shows on resource tiles and clears when a building is placed
3. No `TileMap` node errors in the Godot output log
4. Search codebase: `grep -r "TileMap" --include="*.gd"` must return zero matches (only `TileMapLayer` is acceptable)

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: WorldGrid data model (reads grid data via `get_terrain`, `get_resource`)
- Story 002: `generate(seed)` — generation must be done before rendering can sync
- Story 003: `place_building` — placement logic lives in WorldGrid; rendering reaction is wired here
- Final art assets: Terrain and resource atlas textures are placeholder colored rectangles for VS

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Manual verification steps (Visual/Feel type).*

- **Rendering AC-A**: No TileMap nodes in scene
  - Setup: Open `MapRoot.tscn` in Godot editor
  - Verify: Scene tree shows 4 `TileMapLayer` children (`BackgroundLayer`, `TerrainLayer`, `ResourceOverlay`, `BuildingSlots`); no `TileMap` node anywhere
  - Pass condition: Zero `TileMap` nodes; four `TileMapLayer` nodes present

- **Rendering AC-B**: All tiles set after generation
  - Setup: Run game and trigger world generation
  - Verify: All 900 tiles in the 30×30 grid have visible terrain (no empty/invisible tiles at any position)
  - Pass condition: Consistent visual coverage — no black gaps in the tile grid

- **Rendering AC-C**: Y-sort enabled, no YSort node
  - Setup: Open `MapRoot.tscn` in editor
  - Verify: `MapRoot.y_sort_enabled` is checked in inspector; no `YSort` class nodes anywhere in scene
  - Pass condition: Inspector shows y_sort_enabled = true; scene tree has no nodes of type `YSort`

- **Rendering AC-D**: Resource visual clears when building placed on clearable tile
  - Setup: Run game; find a TREE or BERRY tile; place a building on it
  - Verify: The resource tile visual (tree/berry sprite) disappears when the building is placed
  - Pass condition: No orphaned resource overlay cell remains after building placement

- **Rendering AC-E**: Distinct terrain type visuals
  - Setup: Run game; generate a map with seed 42
  - Verify: EMPTY, TREE, STONE, BERRY, GRASS, IMPASSABLE tiles are visually distinguishable by color/pattern
  - Pass condition: A person can identify each tile type without reading debug labels

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: `production/qa/evidence/grid-tilemap-rendering-evidence.md` + sign-off
Evidence should include: screenshot of generated map with all terrain types visible, confirmation of no TileMap nodes, confirmation of Y-sort setup.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (WorldGrid class with read API), Story 002 must be DONE (generation fills arrays that rendering syncs from)
- Unlocks: Camera System stories (camera needs a scene to render), Building System visual feedback (placement preview uses TileMapLayer)

## Completion Notes
**Completed**: 2026-05-25
**Criteria**: 4/5 passing (AC-D deferred — place_building stub; wires in Story 003)
**Deviations**: Manifest version not set (written pre-manifest); forced-fix warning on seed 42 placeholder (non-blocking)
**Test Evidence**: Visual/Feel — `production/qa/evidence/grid-tilemap-rendering-evidence.md`
**Code Review**: Complete (lean mode — /code-review run earlier this session; all suggestions applied)
**Engine fixes applied**: FastNoise → FastNoiseLite; untyped loop vars; seed/name parameter shadows

**Post-completion change (2026-05-27)**: Added `BackgroundLayer` (TileMapLayer) as first child of MapRoot, below existing TerrainLayer. BackgroundLayer always renders EMPTY (grass) for every tile. TerrainLayer now renders only non-EMPTY terrain types; transparent areas of feature PNGs (trees, stone etc.) composite over BackgroundLayer via GPU alpha. CPU-side compositing code (`_remove_background`, `_blend_over`, `_TERRAIN_BASE_TYPE`) removed. `_build_terrain_tileset()` simplified to single pass. BackgroundLayer and TerrainLayer share the same TileSet resource. AC-A updated: 4 TileMapLayer nodes are now expected.

**Post-completion change (2026-05-28)**: `ResourceOverlay` TileMapLayer is no longer used for resource rendering — it has no TileSet assigned and renders nothing. Resources are now displayed as Sprite2D badge nodes spawned at runtime into a `ResourceBadges` (Node2D, z_index 1) container child of MapRoot. Each badge covers one resource tile and contains per-resource Sprite2D pairs (black backdrop circle + icon). Badge positions are tile-centre-aligned; all badges in the container animate with a continuous sine-wave vertical float (±4 px, 2.5 s period, staggered phase per tile). Multiple resources on the same tile are scattered randomly within the tile bounds using a deterministic RNG seeded by tile position. Data model change: `WorldGrid._resources[x][y]` now stores `Array[ResourceTileData]` (previously `ResourceTileData|null`); `get_resource()` renamed `get_resources()` returning `Array`. Generation changed: instead of every terrain tile yielding one resource, one tile per terrain type is selected deterministically and receives 3 stacked resources of that type.
