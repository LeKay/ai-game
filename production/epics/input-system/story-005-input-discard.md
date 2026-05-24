# Story 005: Input Discard in PAUSED and UI_ACTIVE Contexts

> **Epic**: Input System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: N/A

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-input-002`, `TR-input-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: _unhandled_input() checks current context before dispatching. PAUSED context ignores all non-pause actions. UI_ACTIVE discards non-UI unhandled events. Mouse→tile conversion gated by InputContext context check.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Dual-focus system (4.6) — InputContext treats keyboard/gamepad and mouse as equivalent. _unhandled_input() only receives events not consumed by Control nodes. Verify mouse clicks on UI buttons don't reach world tile.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern for Foundation systems
- Guardrail: Performance budget 0.001ms per context check

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- **GIVEN** the game is PAUSED, **WHEN** player presses WASD or clicks world tile, **THEN** no movement or interaction events fire (inputs ignored in PAUSED context)
- **GIVEN** player clicks a UI button, **WHEN** there is a world tile beneath the button, **THEN** only the UI button receives the click (world tile does NOT trigger `interact` event)
- PAUSED context discards all non-pause actions
- UI_ACTIVE context discards non-UI actions (WASD while menu open)
- Mouse clicks on UI buttons do not reach world tiles (Control node consumes the event)
- WORLD_ACTIVE context allows all non-UI actions through

---

## Implementation Notes

*Derived from ADR-0003 Implementation Guidelines:*

- `_unhandled_input(event)` context gating flow:
  1. Check if global action (pause_toggle, speed controls) → always dispatch
  2. Get current context from stack top
  3. If PAUSED: check if event is a pause action → dispatch if yes, return if no
  4. If WORLD_ACTIVE: dispatch the event
  5. If UI_ACTIVE: all UI events are consumed by Control nodes (not unhandled). If unhandled event reaches here, discard it.
- Mouse clicks on Control nodes (UI buttons) are consumed by Godot's focus system and NEVER reach `_unhandled_input()` — this is Godot's built-in behavior, no additional gating needed
- World tile clicks only reach `_unhandled_input()` when context is WORLD_ACTIVE and no Control node is at the click position
- Use `_is_global_action(event)` helper to identify pause_toggle and speed controls
- Use `_is_pause_action(event)` helper to identify actions relevant to PAUSED context

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Core context stack (input discard depends on context stack)
- [Story 002]: Debounce (separate concern)
- [Story 003]: Rebinding (does not affect discard behavior)
- [Story 004]: Context transitions (discard uses context stack but tests the gate logic)
- Mouse→tile coordinate conversion math (delegated to CameraController per ADR)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: PAUSED context discards movement input
  - Given: Context is PAUSED, InputContext has WORLD_ACTIVE pushed (stack depth 2)
  - When: _unhandled_input() receives move_up event
  - Then: event is NOT dispatched (discarded); no action event fires to subscribers
  - Edge cases: pause_toggle in PAUSED → unhandled (use Space to unpause via global action); move_left in PAUSED → discarded

- **AC-2**: PAUSED context allows pause actions via global path
  - Given: Context is PAUSED
  - When: _unhandled_input() receives pause_toggle event (Space key)
  - Then: event IS dispatched via global action path
  - Edge cases: speed_increase in PAUSED → also dispatched; interact in PAUSED → discarded (not global, not pause action)

- **AC-3**: UI_ACTIVE context discards WASD input
  - Given: Context is UI_ACTIVE (menu open)
  - When: _unhandled_input() receives move_up event
  - Then: event is discarded (non-UI unhandled event in UI context)
  - Edge cases: UI_CONFIRM in UI_ACTIVE → consumed by Control nodes, never reaches _unhandled_input; world tile click in UI_ACTIVE → no interact event (Control nodes at that position consume the click)

- **AC-4**: WORLD_ACTIVE context allows all non-UI actions
  - Given: Context is WORLD_ACTIVE
  - When: _unhandled_input() receives interact event
  - Then: event IS dispatched to subscribers
  - Edge cases: camera_pan in WORLD_ACTIVE → dispatched; speed controls → also dispatched (global)

- **AC-5**: Mouse clicks on UI buttons don't reach world tiles
  - Given: UI button is positioned over a harvestable world tile
  - When: player clicks the UI button
  - Then: Control node consumes the event; _unhandled_input() never receives it; world tile does NOT trigger interact
  - Edge cases: click on world tile (no UI at that position) in WORLD_ACTIVE → _unhandled_input() receives the event; click on world tile in UI_ACTIVE → event discarded by context gate

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/input/input_discard_test.gd` — must exist and pass

**Status**: [ ] Not created

---

## Dependencies

- Depends on: Story 001 must be DONE
- Unlocks: None
