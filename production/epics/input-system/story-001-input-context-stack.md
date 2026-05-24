# Story 001: Input Context Stack and Action Dispatch

> **Epic**: Input System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: N/A

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-input-001`, `TR-input-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: InputContext as Autoload singleton with push/pop context stack using an Array-based stack, Godot InputMap for action definitions, StringName constants for action names.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: SDL3 backend (4.5) — gamepad button mapping may differ. Dual-focus system (4.6) — InputContext is dual-focus agnostic; only asks "what context am I in?" Keyboard and mouse are equivalent for context gating.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern for Foundation systems
- Required: StringName constants for all action IDs
- Guardrail: Performance budget 0.001ms per context check

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- **GIVEN** the game is in WORLD_ACTIVE context, **WHEN** player presses `W`, **THEN** `on_action_pressed("move_up")` event fires, Player Character System receives event and moves character north
- **GIVEN** player remaps `move_up` from `W` to `↑` in Settings, **WHEN** player presses `↑`, **THEN** `on_action_pressed("move_up")` fires (W no longer triggers movement)
- **GIVEN** player rebinds `pause_toggle` to a key already bound to `camera_pan`, **WHEN** prompted "Override binding?", **THEN** if yes: swap bindings; if no: cancel rebind, preserve existing
- InputContext defaults to WORLD_ACTIVE on construction
- InputContext supports push_context/pop_context with stack semantics
- context_changed signal fires on context transition, does NOT fire when context is unchanged
- Global actions (pause_toggle, speed_increase, speed_decrease) always pass through regardless of context
- InputContext integrates with Godot `_unhandled_input()` to gate events

---

## Implementation Notes

*Derived from ADR-0003 Implementation Guidelines:*

- Use `extends Node` as Autoload singleton, registered in project settings as `InputContext`
- Context stack: `var _context_stack: Array[Context] = [Context.WORLD_ACTIVE]`
- Context enum: `enum Context { WORLD_ACTIVE, UI_ACTIVE, PAUSED }`
- `get_current()` returns `_context_stack.back()`
- `push_context(ctx)`: append to stack, emit `context_changed` only if top changes
- `pop_context()`: pop back if size > 1, emit `context_changed` with restored value
- `is_context_active(ctx)`: `_context_stack.back() == ctx`
- Use Godot InputMap for action definitions — configure in editor
- Action constants in `constants/input_actions.gd` as `static var` with `&"action_name"`
- Integrate via `_unhandled_input()`: global actions bypass context check; PAUSED context only allows pause actions; UI_ACTIVE discards non-UI unhandled events

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 002]: Debounce timer logic (separate from context stack)
- [Story 003]: Keybinding persistence to file (rebinding UI is out of scope)
- [Story 005]: Input discard behavior in specific contexts (uses context stack but is a separate testable concern)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: Default context is WORLD_ACTIVE
  - Given: InputContext is constructed/loaded
  - When: get_current() is called
  - Then: returns Context.WORLD_ACTIVE
  - Edge cases: stack size is 1 after construction

- **AC-2**: Push/pop context with correct stack semantics
  - Given: InputContext is in WORLD_ACTIVE
  - When: push_context(UI_ACTIVE) called, then get_current()
  - Then: returns Context.UI_ACTIVE
  - Edge cases: pop_context restores WORLD_ACTIVE; double push → UI_ACTIVE then PAUSED → pop restores WORLD_ACTIVE (not UI_ACTIVE)

- **AC-3**: context_changed signal fires on context transition
  - Given: InputContext is in WORLD_ACTIVE
  - When: push_context(UI_ACTIVE) called
  - Then: context_changed signal fires with UI_ACTIVE argument
  - Edge cases: pushing same context does NOT fire signal; pop that restores same context does NOT fire signal

- **AC-4**: Global actions pass through all contexts
  - Given: Context is UI_ACTIVE
  - When: _unhandled_input() receives pause_toggle event
  - Then: event is dispatched (not discarded)
  - Edge cases: speed_increase/speed_decrease also pass through; in PAUSED context only pause actions pass

- **AC-5**: Input mapping works with Godot InputMap
  - Given: InputMap action "move_up" is bound to Key.W
  - When: player presses W and InputContext is WORLD_ACTIVE
  - Then: dispatch fires with action_id "move_up"
  - Edge cases: action not in InputMap → no dispatch; action bound to multiple keys → all keys trigger same action

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/input/input_context_stack_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None
- Unlocks: Story 002, Story 003, Story 004, Story 005
