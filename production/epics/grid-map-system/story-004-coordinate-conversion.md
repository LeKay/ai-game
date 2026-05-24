# Story 004: Coordinate Conversion

> **Epic**: Grid/Map System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/grid-map-system.md`
**Requirement**: `TR-grid-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: Grid Map Data Model and TileMapLayer Rendering
**ADR Decision Summary**: `tile_to_world(tile) -> Vector2` returns tile center (`tile * TILE_SIZE + TILE_SIZE / 2`). `world_to_tile(world_pos) -> Vector2i` uses `floor()`. Mouse-to-tile conversion goes through: `screen_pos → world_pos (camera offset + zoom) → tile`. TILE_SIZE = 48 pixels.

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: All math used (`floor`, `Vector2`, `Vector2i`, integer arithmetic) is stable across Godot versions. The `floori()` built-in for integer floor is available in Godot 4.x. Confirm `floori()` behavior for negative values (world_pos outside grid → negative tile coords which is_in_bounds will catch).

**Control Manifest Rules (this layer)**:
- Required: N/A — no control manifest exists yet
- Forbidden: Camera state read from inside GridMap; coordinate conversion duplicated in consuming systems
- Guardrail: Conversion must be exact — AC #12 and #13 assert specific pixel values with no tolerance

---

## Acceptance Criteria

*From GDD `design/gdd/grid-map-system.md`, scoped to this story:*

- [ ] **AC-12**: Given TILE_SIZE = 48, when converting tile (5, 12) to pixel coordinates, then result is (264, 600) — the center of the tile
- [ ] **AC-13**: Given TILE_SIZE = 48, when converting pixel (400, 300) to tile coordinates, then result is Vector2i(8, 6)
- [ ] **AC-14**: Given screen_pos = (400, 300), camera_offset = (0, 0), camera_zoom = 1.0, TILE_SIZE = 48, when converting through world position, then result is Vector2i(8, 6)

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

Add to `GridMap` class:

```gdscript
func tile_to_world(tile: Vector2i) -> Vector2:
    # Returns the pixel center of the tile
    return Vector2(tile) * TILE_SIZE + Vector2(TILE_SIZE / 2, TILE_SIZE / 2)

func world_to_tile(world_pos: Vector2) -> Vector2i:
    # floor() maps any pixel within the tile to the tile's top-left corner
    return Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))
```

**Mouse-to-tile conversion** (documentation only — GridMap provides the formula; Camera and Input systems call `world_to_tile` with the result):
```
world_pos = camera_offset + (screen_pos / camera_zoom)
tile_coord = grid_map.world_to_tile(world_pos)
```
GridMap does NOT own camera state. Consuming systems (Camera, Input) handle `camera_offset` and `camera_zoom` before calling `world_to_tile`.

**Exact pixel math** (AC #12 verification):
```
tile_to_world(Vector2i(5, 12)):
  = Vector2(5, 12) * 48 + Vector2(24, 24)
  = Vector2(240, 576) + Vector2(24, 24)
  = Vector2(264, 600)  ✓
```

**Exact pixel math** (AC #13 verification):
```
world_to_tile(Vector2(400, 300)):
  x = floori(400 / 48) = floori(8.333...) = 8
  y = floori(300 / 48) = floori(6.25) = 6
  = Vector2i(8, 6)  ✓
```

**Off-by-one safety**: `floori()` is used (not `roundi()`). Pixel 48 converts to tile 1 (start of tile 1, not tile 0). Pixel 47 converts to tile 0. This is correct — tile 0 occupies pixels 0–47.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: TILE_SIZE constant (defined there; referenced here)
- Story 005: Spatial queries (get_tiles_in_radius, find_nearest) that use tile coordinates

*Camera offset and zoom application are the responsibility of Camera System and Input System — not GridMap.*

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-12**: tile_to_world exact pixel center
  - Given: TILE_SIZE = 48
  - When: `tile_to_world(Vector2i(5, 12))`
  - Then: result == Vector2(264.0, 600.0)
  - Edge cases: `tile_to_world(Vector2i(0, 0))` == Vector2(24, 24); `tile_to_world(Vector2i(29, 29))` == Vector2(1416, 1416)

- **AC-13**: world_to_tile floor conversion
  - Given: TILE_SIZE = 48
  - When: `world_to_tile(Vector2(400, 300))`
  - Then: result == Vector2i(8, 6)
  - Edge cases: `world_to_tile(Vector2(0, 0))` == Vector2i(0, 0); `world_to_tile(Vector2(47.9, 47.9))` == Vector2i(0, 0); `world_to_tile(Vector2(48, 48))` == Vector2i(1, 1)

- **AC-14**: Mouse-to-tile with camera identity (no offset, no zoom)
  - Given: TILE_SIZE = 48, camera_offset = Vector2(0, 0), camera_zoom = 1.0
  - When: world_pos = camera_offset + (Vector2(400, 300) / camera_zoom) = Vector2(400, 300); `world_to_tile(world_pos)`
  - Then: result == Vector2i(8, 6)
  - Edge cases: With camera_zoom = 2.0 and screen_pos (400, 300): world_pos = (200, 150); tile = Vector2i(4, 3)

- **Round-trip consistency**:
  - Given: Any tile at Vector2i(t_x, t_y) where 0 <= t_x, t_y <= 29
  - When: `world_to_tile(tile_to_world(tile))`
  - Then: result == original tile (round-trip is lossless)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/grid/grid_coordinate_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE (TILE_SIZE constant and GridMap class must exist)
- Unlocks: Camera System stories (use `world_to_tile` for screen→tile conversion), Input System (mouse click → tile)
