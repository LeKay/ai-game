# Story 005: Fit-to-View Reset

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-05-14

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: `R` key is a camera action registered in the InputMap. Camera processes it only in WORLD_ACTIVE context. All camera transitions are instantaneous (no lerp).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: InputMap action registration and `Input.is_action_just_pressed()` are stable. No post-cutoff risk.

**Control Manifest Rules (Core layer)**:
- Required: Gate on `InputContext.get_current() == WORLD_ACTIVE` — R key has no effect in UI_ACTIVE or PAUSED
- Required: StringName action constant — declare `camera_reset` in `constants/input_actions.gd`, never use string literal `"camera_reset"`
- Forbidden: No `lerp()` — the fit-to-view transition must be instantaneous per GDD design decision

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story:*

- [ ] **AC-FV-1**: GIVEN a 1920×1080 screen with a 1440×1440 world, WHEN `fit_to_view()` is called, THEN zoom is set to `0.85` (MIN_ZOOM, because `min(1920/1440, 1080/1440) = 0.75 < MIN_ZOOM`) and `camera_offset` is `Vector2(0, 85)` (y-centred: `(1440 - 1080/0.85) / 2 = (1440 - 1271) / 2 = 84.7 ≈ 85`, x-locked to 0 because view > map width)
- [ ] **AC-FV-2**: GIVEN the R key is pressed in WORLD_ACTIVE context, WHEN `_unhandled_input()` processes the event, THEN `fit_to_view()` is called immediately and the viewport updates in the same frame
- [ ] **AC-FV-3**: GIVEN the R key is pressed in UI_ACTIVE or PAUSED context, WHEN `_unhandled_input()` processes the event, THEN `fit_to_view()` is NOT called (input is swallowed by InputContext gate)

---

## Implementation Notes

*Derived from GDD section "10. Fit-to-View (Reset Camera)":*

```gdscript
func fit_to_view() -> void:
    # Compute ideal zoom to fit the full map on screen
    var ideal_zoom: float = min(
        float(screen_width) / float(MAX_X),
        float(screen_height) / float(MAX_Y)
    )
    zoom = clamp(ideal_zoom, MIN_ZOOM, MAX_ZOOM)

    # Recompute view dimensions at clamped zoom
    var view_width: float  = float(screen_width)  / zoom
    var view_height: float = float(screen_height) / zoom

    # Centre the camera on the map
    camera_offset.x = (float(MAX_X) - view_width)  / 2.0
    camera_offset.y = (float(MAX_Y) - view_height) / 2.0

    # Apply boundary clamp — handles case where view > map (forces offset to 0)
    _apply_boundary_clamp()
```

**Constants:**
- `MAX_X = GRID_SIZE * TILE_SIZE = 1440`
- `MAX_Y = GRID_SIZE * TILE_SIZE = 1440`
- `MIN_ZOOM = 0.85`, `MAX_ZOOM = 2.0`

**1920×1080 worked example (from GDD):**
- `ideal_zoom = min(1920/1440, 1080/1440) = min(1.33, 0.75) = 0.75`
- `0.75 < MIN_ZOOM` → `zoom = 0.85`
- `view_width = 1920/0.85 = 2259 > MAX_X` → x-offset locked to 0 by clamp
- `view_height = 1080/0.85 = 1271 < MAX_Y` → y-offset = `(1440 - 1271)/2 = 84.7`

**Key binding:** Register `camera_reset` action in the InputMap with default key `R`. Add the `StringName` constant to `constants/input_actions.gd`. Listen in `_unhandled_input()`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- **Story 003**: `_apply_boundary_clamp()` is called inside `fit_to_view()` — the clamping logic must already be implemented
- **Story 002**: Zoom state (`zoom` variable) must already exist

---

## QA Test Cases

*Written at story creation. Implement against these cases.*

- **AC-FV-1**: fit_to_view result on 1920×1080 screen
  - Given: `CameraController` on a 1920×1080 screen, `GRID_SIZE = 30`, `TILE_SIZE = 48`, `MIN_ZOOM = 0.85`, any current `camera_offset` and `zoom`
  - When: `fit_to_view()` is called
  - Then: `zoom == 0.85`, `camera_offset.x == 0.0` (±0.5), `camera_offset.y ≈ 84.7` (±0.5)
  - Edge cases: Called when already at fit-to-view state → idempotent (same result); called at MAX_ZOOM → zoom snaps to 0.85

- **AC-FV-2**: R key in WORLD_ACTIVE triggers fit_to_view
  - Given: `InputContext == WORLD_ACTIVE`, camera at arbitrary offset and zoom
  - When: `camera_reset` action fires (InputEventKey with `R`, `is_action_just_pressed == true`)
  - Then: `zoom == 0.85`, `camera_offset` matches fit-to-view result for current screen size
  - Edge cases: Key held down → only triggers on `just_pressed`, not every frame (use `is_action_just_pressed` not `is_action_pressed`)

- **AC-FV-3**: R key blocked in UI_ACTIVE / PAUSED
  - Given: `InputContext == UI_ACTIVE`
  - When: `camera_reset` action fires
  - Then: `zoom` and `camera_offset` are unchanged (fit_to_view was not called)
  - Edge cases: PAUSED context → same behaviour (no effect)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/camera/fit_to_view_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (zoom state), Story 003 (boundary clamp called inside fit_to_view)
- Unlocks: None — final camera story

## Completion Notes
**Completed**: 2026-05-28
**Criteria**: 3/3 passing
**Deviations**: ADR-0003 missing (pre-existing); TILE_SIZE/GRID_SIZE hardcoded (pre-existing)
**Test Evidence**: Logic — `tests/unit/camera/fit_to_view_test.gd` (10 tests, all ACs covered)
**Code Review**: Complete (lean mode — LP-CODE-REVIEW gate skipped; manual review applied fixes: InputActions.CAMERA_RESET constant, unclamped zoom test, boundary clamp comment)
