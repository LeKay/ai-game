# Story 004: Coordinate Conversion

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: Mouse→tile conversion is delegated to CameraController. Input System calls `CameraController.get_tile_at_screen(screen_pos)` — this is the public API that all downstream systems (Building, HUD, Hover) consume.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Vector2i`, `floor()`, and `clamp()` are unchanged since Godot 4.0. No post-cutoff risk.

**Control Manifest Rules (Core layer)**:
- Required: Method must be callable from any context — `screen_to_tile()` and `tile_to_screen()` are pure query functions with no side effects; they must not gate on InputContext
- Forbidden: Never call `TileMapLayer.get_cell()` for coordinate conversion — use pure math from `camera_offset`, `zoom`, and `TILE_SIZE`

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN camera at offset `(0, 0)` with `zoom = 1.0`, WHEN `screen_to_tile(Vector2(264, 600))` is called, THEN result is `Vector2i(5, 12)`
- [ ] **AC-2**: GIVEN camera at offset `(0, 0)` with `zoom = 1.0`, WHEN `tile_to_screen(Vector2i(5, 12))` is called, THEN result is `Vector2(264.0, 600.0)` (tile centre)
- [ ] **AC-11**: GIVEN `camera_offset = (0, 0)`, `zoom = 1.0` on a 1920×1080 screen, WHEN `screen_to_tile(Vector2(1800, 500))` is called, THEN result is `Vector2i(29, 10)` (rightmost column — `1800/48 = 37.5` → clamped to 29; `500/48 = 10.4` → 10)

---

## Implementation Notes

*Derived from GDD Formulas section:*

**screen_to_tile (public API — primary query for click→tile):**
```gdscript
func screen_to_tile(screen_pos: Vector2) -> Vector2i:
    var world_pos: Vector2 = camera_offset + (screen_pos / zoom)
    var tile: Vector2i = Vector2i(
        floori(world_pos.x / TILE_SIZE),
        floori(world_pos.y / TILE_SIZE)
    )
    return tile.clamp(Vector2i(0, 0), Vector2i(GRID_SIZE - 1, GRID_SIZE - 1))
```

**tile_to_screen (for rendering objects at correct screen position):**
```gdscript
func tile_to_screen(tile_pos: Vector2i) -> Vector2:
    var world_pos: Vector2 = Vector2(tile_pos) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) / 2.0
    return (world_pos - camera_offset) * zoom
```

**Constants** (read from GridMap Autoload — do not hardcode):
- `TILE_SIZE = 48`
- `GRID_SIZE = 30`

Both methods are pure — no side effects, callable from any context. They depend only on `camera_offset` and `zoom` (CameraController internal state) and the GridMap constants.

**OOB clamping:** When `screen_to_tile` is called with a screen position outside the visible map area (e.g., empty screen pixels at low zoom where the view exceeds the map), the `clamp()` call returns the nearest valid tile edge. This is intentional — clicking in empty screen space returns the nearest map tile, which game logic can then ignore if desired.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- **Story 003**: Boundary clamping of `camera_offset` — conversion results depend on a clamped offset, but clamping is not owned here
- **Story 005**: `fit_to_view()` — uses `tile_to_screen` indirectly but is a separate feature

---

## QA Test Cases

*Written at story creation. Implement against these cases.*

- **AC-1**: screen_to_tile known value
  - Given: `camera_offset = Vector2(0, 0)`, `zoom = 1.0`, `TILE_SIZE = 48`, `GRID_SIZE = 30`
  - When: `screen_to_tile(Vector2(264, 600))` is called
  - Then: Returns `Vector2i(5, 12)`
  - Derivation: `world_pos = (0,0) + (264,600)/1.0 = (264,600)`. `tile = floor(264/48, 600/48) = floor(5.5, 12.5) = (5, 12)`. No clamp needed.
  - Edge cases: `screen_pos = (0, 0)` → `Vector2i(0, 0)`; `screen_pos = (1439, 1439)` at zoom 1.0, offset (0,0) → `Vector2i(29, 29)` (last tile)

- **AC-2**: tile_to_screen known value
  - Given: `camera_offset = Vector2(0, 0)`, `zoom = 1.0`, `TILE_SIZE = 48`
  - When: `tile_to_screen(Vector2i(5, 12))` is called
  - Then: Returns `Vector2(264.0, 600.0)` (tile centre: `5*48 + 24 = 264`, `12*48 + 24 = 600`)
  - Edge cases: Tile at `(0, 0)` → `Vector2(24, 24)` (centre of top-left tile); tile off-screen (negative screen_pos) is valid output — caller decides whether to render

- **AC-11**: Out-of-bounds screen position clamped to nearest edge tile
  - Given: `camera_offset = Vector2(0, 0)`, `zoom = 1.0`, `TILE_SIZE = 48`, `GRID_SIZE = 30`
  - When: `screen_to_tile(Vector2(1800, 500))` is called
  - Then: Returns `Vector2i(29, 10)` (`1800/48 = 37.5 → floor = 37`, clamped to 29; `500/48 = 10.4 → floor = 10`, within bounds)
  - Edge cases: Negative screen position → `Vector2i(0, 0)` (clamped); both axes OOB → clamped to corner tile `(29, 29)`

- **Roundtrip consistency**: `tile_to_screen(screen_to_tile(p)) ≠ p` in general (floor loses sub-tile precision), but `screen_to_tile(tile_to_screen(t)) == t` for all valid tile coords
  - Given: Any valid `Vector2i` tile `t` in `[(0,0), (29,29)]`, offset `(0,0)`, zoom `1.0`
  - When: `screen_to_tile(tile_to_screen(t))` is called
  - Then: Result equals `t` (roundtrip is exact for tile-centre screen positions)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/camera/coordinate_conversion_test.gd` — must exist and pass

**Status**: [x] PASSED — `tests/unit/camera/coordinate_conversion_test.gd` (11 tests)

---

## Dependencies

- Depends on: Story 001 (CameraController must have `camera_offset` and `zoom` state), Story 003 (offset must be clamped before conversion produces meaningful results)
- Unlocks: Building System placement preview, HUD hover tooltips, Manual Labor tile targeting (all consume `screen_to_tile()`)

## Completion Notes
**Completed**: 2026-05-28
**Criteria**: 3/3 passing
**Deviations**: ADVISORY — TILE_SIZE/GRID_SIZE hardcoded constants (pre-existing, accepted pending WorldGrid singleton); ADR-0003 not on disk (known gap from Stories 001–003)
**Test Evidence**: Logic — `tests/unit/camera/coordinate_conversion_test.gd` (11 tests, all passing)
**Code Review**: Complete (this session — APPROVED WITH SUGGESTIONS; suggestions applied before story-done)
