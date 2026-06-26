# Story 001: Pan Input

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: InputContext uses a push/pop stack (WORLD_ACTIVE / UI_ACTIVE / PAUSED). Camera pan is only active when context is WORLD_ACTIVE. Mouse position→tile conversion is delegated to CameraController.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Camera2D pan/zoom API is stable across 4.4–4.6. InputContext gating uses `push_context()`/`pop_context()` — see ADR-0003. SDL3 gamepad backend (4.5) is transparent for pan (WASD/arrow keys).

**Control Manifest Rules (Core layer)**:
- Required: Subscribe to input via `_unhandled_input()` or `InputContext` — not direct polling in `_process()`
- Required: `Autoload dependency injection via _enter_tree()` — cache InputContext reference, null-check
- Forbidden: Never use OS-level clock for movement timing — use `delta` from `_process()`

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story:*

- [ ] **AC-5**: GIVEN `pan_speed_tiles_per_second = 8`, WHEN `_process(delta)` is called with injected `delta = 0.01667`, THEN camera displacement = `8 × 48 × 0.01667 = 6.399` pixels (~6.4 px per frame)
- [ ] **AC-6**: GIVEN `edge_zone_width = 20` and camera in WORLD_ACTIVE context, WHEN mouse `y > screen_height - 20` (bottom edge zone) and `_process(delta)` is called with `delta = 0.01667`, THEN camera downward displacement = `2 × 48 × 0.01667 = 1.599` pixels (~1.6 px per frame)
- [ ] **AC-8**: GIVEN mouse cursor leaves the game window while edge scrolling was active, WHEN the mouse-exit event fires, THEN edge scrolling stops immediately (camera no longer pans on next `_process()` call)

---

## Implementation Notes

*Derived from GDD Detailed Design and ADR-0003:*

Three pan input sources, all processed in `_process(delta)`, all additive:

1. **WASD / Arrow keys**: Listen for `on_action_held` for `move_up`/`move_down`/`move_left`/`move_right` (and arrow equivalents). Per-frame delta: `pan_speed × TILE_SIZE × delta`. Frame-rate independent.

2. **Middle mouse drag**: Track mouse position delta between `_unhandled_input()` calls with middle button held. Convert screen-space delta to world-space by dividing by `zoom`. Apply to camera offset directly.

3. **Edge scrolling**: Each frame, check mouse cursor position against `edge_zone_width` threshold on all 4 screen edges. Apply `edge_scroll_speed × TILE_SIZE × delta` in the corresponding direction. Edge scroll speed defaults to `0.25 × pan_speed`.

**Edge scroll suppression:** Edge scrolling must be suppressed when mouse is over any UI node (`Control` node with `mouse_filter != MOUSE_FILTER_IGNORE`). Use `get_viewport().gui_get_focus_owner()` or check `gui_get_hovered_control()` to detect UI hover.

**Mouse-leave guard:** Track `mouse_inside_window` flag. On `NOTIFICATION_WM_MOUSE_EXIT`, set flag to false, clear edge scroll state. On `NOTIFICATION_WM_MOUSE_ENTER`, set flag to true.

All pan sources gate on `InputContext.get_current() == WORLD_ACTIVE`. Pan has no effect in UI_ACTIVE or PAUSED context.

Boundary clamping is applied after all pan inputs accumulate (handled in Story 003 — do not implement here).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- **Story 003**: Boundary clamping — pan may temporarily push camera out of bounds; clamping is applied at end of frame
- **Story 002**: Zoom handling — scroll wheel events
- **Story 004**: `screen_to_tile()` conversion — not needed for pan

---

## QA Test Cases

*Written at story creation. Implement against these cases.*

- **AC-5**: WASD pan displacement formula
  - Given: `CameraController` with `pan_speed_tiles_per_second = 8`, `TILE_SIZE = 48`, WORLD_ACTIVE context, right key held
  - When: `_process(0.01667)` is called
  - Then: `camera_offset.x` increases by `6.399` pixels (±0.01 tolerance)
  - Edge cases: `delta = 0.0` → no movement; `pan_speed = 0` → no movement; two keys held simultaneously (e.g. right + down) → both axes advance independently

- **AC-6**: Edge scroll displacement formula
  - Given: `CameraController` with `pan_speed = 8`, `edge_zone_width = 20`, screen 1920×1080, WORLD_ACTIVE context, mouse at `(960, 1065)` (within bottom edge zone), no UI hovered
  - When: `_process(0.01667)` is called
  - Then: `camera_offset.y` increases by `1.599` pixels (±0.01 tolerance)
  - Edge cases: mouse exactly at `screen_height - edge_zone_width` → no scroll (boundary is exclusive); mouse over UI Control → no edge scroll

- **AC-8**: Mouse-leave stops edge scroll
  - Given: Edge scroll was active (mouse in edge zone, scroll displacement accumulating)
  - When: `NOTIFICATION_WM_MOUSE_EXIT` fires
  - Then: Next `_process()` call produces zero edge-scroll displacement (camera does not continue to pan)
  - Edge cases: Mouse re-enters window near edge → edge scroll resumes on next `_process()` if still in zone

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/camera/pan_input_test.gd` — must exist and pass

**Status**: [x] `tests/unit/camera/pan_input_test.gd` — 12 tests, all ACs covered

---

## Dependencies

- Depends on: None (first camera story — `CameraController` scaffold can be created here)
- Unlocks: Story 002 (Zoom), Story 003 (Boundary Clamping)

---

## Completion Notes

**Completed**: 2026-05-27
**Criteria**: 3/3 passing (AC-5, AC-6, AC-8 — all covered by automated tests)
**Deviations**:
- ADVISORY: `TILE_SIZE: int = 48` hardcoded const — suggest externalising to shared `GameConstants` resource
- ADVISORY: `0.25` edge scroll speed multiplier is a magic number inline at `camera_controller.gd:103` — suggest naming as `EDGE_SCROLL_SPEED_FACTOR`
- ADVISORY: `pan_speed_tiles_per_second` and `edge_zone_width` not `@export` — editor tuning blocked until exported
**Test Evidence**: Logic — `tests/unit/camera/pan_input_test.gd` (12 tests, 3 ACs covered)
**Code Review**: Skipped — Lean mode
