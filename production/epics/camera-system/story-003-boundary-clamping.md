# Story 003: Boundary Clamping

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: CameraController owns all viewport state. GridMap provides `GRID_SIZE` and `TILE_SIZE` constants used to compute world bounds.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `get_viewport().get_visible_rect()` provides current window dimensions. No post-cutoff risk for viewport size queries.

**Control Manifest Rules (Core layer)**:
- Required: Gate on `InputContext.get_current() == WORLD_ACTIVE` for pan; clamping applies regardless of context (it's always enforced)
- Required: Autoload dependency injection — cache GridMap reference in `_enter_tree()` to read `TILE_SIZE` and `GRID_SIZE`

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story:*

- [ ] **AC-4**: GIVEN camera at offset `(500, 300)` with `zoom = 1.5` on a 1920×1080 screen, WHEN boundary clamp is applied, THEN `camera_offset.x = clamp(500, 0, 1440 - 1280) = clamp(500, 0, 160) = 160` (clamped to right boundary)
- [ ] **AC-9**: GIVEN camera at offset `(0, 0)` with `zoom = 1.0` on a 1920×1080 window, WHEN the window is resized to 1280×720, THEN `view_width = 1280`, `view_height = 720`, and `camera_offset` is re-clamped to fit new bounds
- [ ] **AC-10**: GIVEN camera at `zoom = 0.85` (min_zoom) with `camera_offset.x = 0`, WHEN boundary clamp is applied (`view_width = 1920/0.85 = 2259 > MAX_X = 1440`, so `clamp_x = 0`), THEN `camera_offset.x` remains `0` and a pan-right input produces zero displacement
- [ ] **AC-12**: GIVEN window resized from 1920×1080 to 1280×720, WHEN current `camera_offset` was previously valid and remains within the new view bounds, THEN `camera_offset` changes by ≤ 1 pixel (no visible jump — position preserved, only view dimensions update)

---

## Implementation Notes

*Derived from GDD Formulas section — Boundary Clamp:*

```
view_width  = screen_width / zoom
view_height = screen_height / zoom
MAX_X = GRID_SIZE * TILE_SIZE   # 30 * 48 = 1440
MAX_Y = GRID_SIZE * TILE_SIZE   # 1440

# Special case: if view is larger than map in a dimension, lock camera at 0
clamp_x = 0 if view_width  >= MAX_X else clamp(camera_offset.x, 0, MAX_X - view_width)
clamp_y = 0 if view_height >= MAX_Y else clamp(camera_offset.y, 0, MAX_Y - view_height)

camera_offset = Vector2(clamp_x, clamp_y)
```

Call `_apply_boundary_clamp()` at the end of every `_process()` frame, after all pan and zoom inputs have been accumulated. This ensures no intermediate state escapes the clamp.

**Window resize handling:** Connect to `get_viewport().size_changed` signal. On resize, recalculate `screen_width`/`screen_height` from `get_viewport().get_visible_rect().size`, then immediately re-apply boundary clamp. Do not animate — the re-clamp is instantaneous.

**Pan suppression at boundary:** When `view_width >= MAX_X`, any pan-right input must produce zero displacement (camera is locked because the view already shows the full map width). Implement this by applying the clamp after pan accumulation — the math handles it naturally (offset can't exceed 0 in the locked case).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- **Story 001**: Pan input accumulation — clamping is applied after pan, not instead of it
- **Story 002**: Zoom anchor calculation — clamping is applied after zoom anchor

---

## QA Test Cases

*Written at story creation. Implement against these cases.*

- **AC-4**: Right-boundary clamp at zoom 1.5
  - Given: `CameraController` at offset `(500, 300)`, `zoom = 1.5`, screen 1920×1080, `MAX_X = MAX_Y = 1440`
  - When: `_apply_boundary_clamp()` is called
  - Then: `camera_offset.x == 160` (clamped), `camera_offset.y == 300` (unchanged — still within `[0, 1440-720=720]`)
  - Edge cases: offset `(0, 0)` at zoom 1.5 → no clamp needed, offset unchanged; offset `(-10, 0)` → clamped to `(0, 0)` (should not happen in practice but clamp handles it)

- **AC-9**: Window resize re-clamp
  - Given: `CameraController` at offset `(0, 0)`, `zoom = 1.0`, initial screen 1920×1080
  - When: Window resized to 1280×720 (`size_changed` signal fires)
  - Then: `view_width == 1280`, `view_height == 720`; clamp applied with new bounds (`MAX_X - 1280 = 160`, `MAX_Y - 720 = 720`)
  - Edge cases: Resize to screen larger than map → view > MAX in that dimension → offset locked to 0

- **AC-10**: View-exceeds-map locks camera
  - Given: `zoom = 0.85`, `view_width = 1920/0.85 ≈ 2259`, `MAX_X = 1440`, `camera_offset.x = 0`
  - When: `_apply_boundary_clamp()` called, then pan-right input applied and clamp called again
  - Then: `camera_offset.x == 0` after both clamp calls (view exceeds map, locked at 0)
  - Edge cases: `view_width` exactly equals `MAX_X` → locked at 0 (boundary is inclusive)

- **AC-12**: No visible jump on resize
  - Given: `camera_offset = (50, 100)` (valid at 1920×1080, zoom 1.0; `clamp_x ∈ [0, 0]` — wait, at zoom 1.0 view_width=1920 > 1440 so offset locked to 0 anyway)
  - Revised given: zoom 1.5, `camera_offset = (50, 100)` (valid: `clamp_x ∈ [0, 160]`, `clamp_y ∈ [0, 720]`)
  - When: Window resized from 1920×1080 to 1280×720 (`view_width = 1280/1.5 ≈ 853`, `view_height = 720/1.5 = 480`)
  - Then: `camera_offset` unchanged (50 and 100 are still within new clamp bounds `[0, 1440-853=587]` and `[0, 1440-480=960]`)
  - Edge cases: Resize that would push a valid offset out of new bounds → offset is clamped (changes by the minimum amount needed, not reset to 0)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/camera/boundary_clamp_test.gd` — must exist and pass

**Status**: [x] `tests/unit/camera/boundary_clamp_test.gd` — 10 tests, all ACs covered

---

## Dependencies

- Depends on: Story 001 (pan input), Story 002 (zoom — view dimensions depend on zoom value)
- Unlocks: Story 004 (Coordinate Conversion uses the clamped offset), Story 005 (Fit-to-View uses clamping)

---

## Completion Notes

**Completed**: 2026-05-28
**Criteria**: 4/4 passing
**Deviations**: ADVISORY — `TILE_SIZE=48`, `GRID_SIZE=30`, `MIN_ZOOM=0.85`, `MAX_ZOOM=2.0` hardcoded constants (pre-existing from Stories 001/002; pending WorldGrid singleton)
**Test Evidence**: Logic — `tests/unit/camera/boundary_clamp_test.gd` (10 tests, all ACs covered)
**Code Review**: Complete — signal leak fix (`size_changed.disconnect` in `_exit_tree`) applied; `motion.relative / zoom.x` clarity fix applied; lock-to-0 doc comment added
