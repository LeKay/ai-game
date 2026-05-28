# Story 002: Zoom with Mouse Anchor

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: Scroll wheel events flow through InputContext; camera zoom only active in WORLD_ACTIVE context. Mouse position is available as screen-space coordinates from the Input singleton.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Camera2D zoom property is stable. Scroll delta arrives via `_unhandled_input(InputEvent)` — check for `InputEventMouseButton` with `MOUSE_BUTTON_WHEEL_UP`/`WHEEL_DOWN`. No post-cutoff risk.

**Control Manifest Rules (Core layer)**:
- Required: Gate on `InputContext.get_current() == WORLD_ACTIVE` before processing zoom
- Required: Clamp zoom to `[MIN_ZOOM, MAX_ZOOM]` constants — never allow unclamped values
- Forbidden: Never use OS-level clock for zoom interpolation — zoom is instantaneous (no lerp per GDD decision)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story:*

- [ ] **AC-3**: GIVEN camera at offset `(0, 0)` with zoom `1.0`, WHEN scroll wheel delta is `+3.0` with `zoom_sensitivity = 1.0`, THEN `new_zoom = clamp(1.0 + 3.0 × 1.0, 0.85, 2.0) = 2.0` (max zoom reached — clamped)
- [ ] **AC-7**: GIVEN camera at offset `(200, 150)` with zoom `1.0`, WHEN scroll wheel delta is `+2.0` with mouse at screen position `(400, 300)`, THEN `new_zoom = 2.0` AND `camera_offset_new = (400, 300)` (computed via zoom anchor formula — see Implementation Notes)

---

## Implementation Notes

*Derived from GDD Formulas section:*

**Zoom input:**
```
zoom_delta = scroll_delta * settings.scroll_sensitivity * zoom_sensitivity
new_zoom = clamp(current_zoom + zoom_delta, MIN_ZOOM, MAX_ZOOM)
```

**Zoom anchor (keep mouse tile fixed under cursor):**
```
mouse_world_before = (mouse_screen / current_zoom) + camera_offset
camera_offset_new  = mouse_world_before - (mouse_screen / new_zoom)
```

Apply boundary clamping after anchor calculation (Story 003 owns clamping — call `_apply_clamp()` if already implemented, or leave unclamped and document the dependency).

**Constants:**
- `MIN_ZOOM = 0.85`
- `MAX_ZOOM = 2.0`

**No smooth interpolation.** Zoom changes are instantaneous — this is an explicit design decision from the GDD ("no transitions"). Do not add `lerp()`.

**Scroll direction:** Scroll up (`MOUSE_BUTTON_WHEEL_UP`) → positive zoom delta (zoom in). Scroll down (`MOUSE_BUTTON_WHEEL_DOWN`) → negative zoom delta (zoom out). Confirm this matches your platform's scroll convention in testing.

**Scroll delta = 0:** No zoom change — guard against zero delta to avoid unnecessary recalculations.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- **Story 003**: Boundary clamping applied after zoom anchor calculation
- **Story 004**: `screen_to_tile()` — zoom affects coordinate conversion but the API is owned there
- **Story 001**: Pan input handling

---

## QA Test Cases

*Written at story creation. Implement against these cases.*

- **AC-3**: Zoom clamping at max
  - Given: `CameraController` at offset `(0, 0)`, `zoom = 1.0`, `zoom_sensitivity = 1.0`, WORLD_ACTIVE context
  - When: Scroll event fires with delta `+3.0`
  - Then: `zoom == 2.0` (clamped to `MAX_ZOOM`)
  - Edge cases: delta = `+0.001` → zoom increases by 0.001 (not clamped if result < 2.0); scroll at `MAX_ZOOM` → zoom stays at 2.0; scroll at `MIN_ZOOM` with negative delta → zoom stays at 0.85

- **AC-7**: Zoom anchor keeps mouse tile fixed
  - Given: `CameraController` at offset `(200, 150)`, `zoom = 1.0`, mouse screen position `(400, 300)`, WORLD_ACTIVE context
  - When: Scroll event fires with delta `+2.0` (`zoom_sensitivity = 1.0`)
  - Then: `new_zoom == 2.0` AND `camera_offset == Vector2(400, 300)` (±0.01 tolerance)
  - Derivation: `mouse_world_before = (400/1.0 + 200, 300/1.0 + 150) = (600, 450)`. `camera_offset_new = (600, 450) - (400/2.0, 300/2.0) = (600, 450) - (200, 150) = (400, 300)`
  - Edge cases: Mouse at corner `(0, 0)` → anchor at world origin, offset unchanged; mouse at screen center → symmetric anchor

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/camera/zoom_anchor_test.gd` — must exist and pass

**Status**: [x] `tests/unit/camera/zoom_anchor_test.gd` — 10 tests, all passing

---

## Dependencies

- Depends on: Story 001 (CameraController scaffold must exist with `camera_offset` and `zoom` state)
- Unlocks: Story 003 (Boundary Clamping — zoom changes affect view dimensions used in clamp)

## Completion Notes
**Completed**: 2026-05-27
**Criteria**: 2/2 passing
**Deviations**:
- ADVISORY: `settings.scroll_sensitivity` not consulted in zoom delta — interim simplification, no Settings singleton exists yet. Must address before Settings is introduced.
- ADVISORY (pre-existing, Story 001): Gameplay values (`MIN_ZOOM`, `MAX_ZOOM`, `zoom_sensitivity`, `pan_speed_tiles_per_second`) are in-code rather than data-driven.
- ADVISORY (pre-existing, Story 001): Middle mouse drag not context-gated.
**Test Evidence**: Logic — `tests/unit/camera/zoom_anchor_test.gd` (10 tests, all passing)
**Code Review**: Complete — 3 required changes applied (zero-delta guard, `before_test` child order, anchor comment correction)
