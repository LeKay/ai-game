# Story 004: Context Transition on UI Open/Close

> **Epic**: Input System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration
> **Manifest Version**: N/A

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-input-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: push_context(UI_ACTIVE) on UI open, pop_context() on UI close. context_changed signal fires on transition. Nested menus supported via stack depth.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Dual-focus system (4.6) — InputContext treats keyboard/gamepad and mouse input as equivalent for context gating. _unhandled_input() only receives events NOT consumed by Control nodes. Verify UI open/close triggers correct context transitions.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern for Foundation systems
- Guardrail: Stack depth warning when exceeding 3 levels
- Guardrail: Performance budget 0.001ms per context check

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- **GIVEN** player is holding `W` (moving north), **WHEN** player opens menu (presses Escape), **THEN** context switches to UI_ACTIVE, `on_action_released("move_up")` fires, character stops moving
- Context transition on UI open: push_context(UI_ACTIVE) changes active context
- Context transition on UI close: pop_context() restores previous context
- Multiple nested UIs: push_context(UI_ACTIVE) twice → depth 2 → pop once → restores depth 1 → still UI_ACTIVE (not WORLD_ACTIVE)
- Context changed signal fires on both push and pop transitions
- Stack depth warning logged when depth exceeds 3

---

## Implementation Notes

*Derived from ADR-0003 Implementation Guidelines:*

- UI systems call InputContext.push_context(UI_ACTIVE) when opening a menu
- UI systems call InputContext.pop_context() when closing a menu
- Each push/pop is a balanced pair — document this invariant in UI system GDDs
- Stack depth guard: log warning on push_context when _context_stack.size() > 3
- Release all held movement inputs on context transition to WORLD_ACTIVE → UI_ACTIVE:
  - Broadcast on_action_released for active movement keys (W, A, S, D)
  - Prevents character sliding after menu closes
- Pause toggle deferred: pressing Space during UI_ACTIVE queues pause for when context returns to WORLD_ACTIVE

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Core context stack implementation (prerequisite for this story)
- [Story 005]: Input discard in specific contexts (this story handles the transition; discard behavior is tested separately)
- [Story 002]: Debounce logic (separate concern)
- Settings System rebinding (does not affect context transitions)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: Opening a menu transitions to UI_ACTIVE
  - Given: Context is WORLD_ACTIVE, player is holding W
  - When: push_context(UI_ACTIVE) is called
  - Then: get_current() returns UI_ACTIVE; context_changed signal fires with UI_ACTIVE
  - Edge cases: movement release events broadcast when context changes

- **AC-2**: Closing a menu restores previous context
  - Given: Context is UI_ACTIVE (depth 1)
  - When: pop_context() is called
  - Then: get_current() returns WORLD_ACTIVE; context_changed signal fires
  - Edge cases: pop when stack depth is 1 → no-op (no warning)

- **AC-3**: Nested UI menus work correctly
  - Given: Context is WORLD_ACTIVE
  - When: push_context(UI_ACTIVE) → push_context(UI_ACTIVE) → pop_context()
  - Then: stack depth is 2 after double push, depth 1 after pop, get_current() still returns UI_ACTIVE
  - Edge cases: pop until stack depth is 1 → restores WORLD_ACTIVE; depth 0 → never possible (minimum stack depth 1)

- **AC-4**: Stack depth warning at 3+ levels
  - Given: Stack has 3 contexts
  - When: push_context(UI_ACTIVE) is called (depth becomes 4)
  - Then: warning logged to console
  - Edge cases: stack depth exactly 3 → no warning; depth 4 → warning; depth 5 → warning

- **AC-5**: Context transition fires on both push and pop
  - Given: Context is WORLD_ACTIVE
  - When: push_context(UI_ACTIVE) → pop_context()
  - Then: context_changed fires twice — once for UI_ACTIVE, once for WORLD_ACTIVE
  - Edge cases: push same context (WORLD_ACTIVE → WORLD_ACTIVE) → no signal; pop that restores same → no signal

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/input/ui_context_transition_test.gd` — must exist and pass

**Status**: [ ] Not created

---

## Dependencies

- Depends on: Story 001 must be DONE
- Unlocks: None
