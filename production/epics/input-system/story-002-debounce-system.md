# Story 002: Input Debounce System

> **Epic**: Input System
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: N/A

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-input-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: Input Context System and Action Mapping
**ADR Decision Summary**: Timer-based debounce using Dictionary keyed by action name, DEBOUNCE_DELAY = 0.25s, request_debounce() returns true if debounced (discard).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Time.get_ticks_msec() is stable across Godot versions. No post-cutoff APIs used.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern for Foundation systems
- Guardrail: Performance budget 0.001ms per debounce check

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- **GIVEN** player spams Space key 10 times in 1 second, **WHEN** debounce is active (200ms), **THEN** only first press registers, subsequent presses within 200ms ignored (no double-pause bug)
- InputContext.request_debounce(action) returns true if same action requested within DEBOUNCE_DELAY
- InputContext.request_debounce(action) returns false and records timestamp if action is not debounced
- DEBOUNCE_DELAY defaults to 0.25s (250ms)
- Debounce timers are per-action (keyed by StringName)

---

## Implementation Notes

*Derived from ADR-0003 Implementation Guidelines:*

- `_debounce_timers: Dictionary` keyed by StringName, value is float timestamp (seconds)
- `DEBOUNCE_DELAY: float = 0.25`
- `request_debounce(action: StringName) -> bool`:
  - If action in Dictionary: compute elapsed = current_time - last_time
  - If elapsed < DEBOUNCE_DELAY: return true (debounced)
  - Otherwise: update timestamp, return false (action allowed)
- Use `Time.get_ticks_msec() / 1000.0` for current time in seconds
- Called BEFORE dispatching the action
- Timers persist until game ends (no cleanup needed for Vertical Slice)
- Coarse: same 0.25s delay applies to ALL actions (per-action granularity deferred)

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- [Story 001]: Context stack and action dispatch (debounce depends on this story)
- [Story 003]: Keybinding persistence (debounce uses action IDs but does not manage bindings)
- Per-action debounce granularity (not in scope; ADR explicitly notes this is a limitation)

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: First call to request_debounce returns false
  - Given: InputContext in clean state, no prior debounce entries
  - When: request_debounce("pause_toggle") is called
  - Then: returns false; timestamp recorded for "pause_toggle"
  - Edge cases: same call immediately after → returns true (within 0.25s)

- **AC-2**: Debounce expires after DEBOUNCE_DELAY
  - Given: pause_toggle was debounced 0.2s ago
  - When: request_debounce("pause_toggle") is called again (after advancing 0.1s)
  - Then: returns false (total elapsed 0.3s > 0.25s delay)
  - Edge cases: exactly at 0.25s → boundary test; 0.249s → returns true; 0.251s → returns false

- **AC-3**: Different actions have independent debounce timers
  - Given: "pause_toggle" was just debounced (returns false)
  - When: request_debounce("speed_increase") is called
  - Then: returns false (different action, independent timer)
  - Edge cases: same action name but different case → different actions (StringName comparison); pressing same key for different actions (not possible with InputMap)

- **AC-4**: Rapid spam of 10 presses within 1 second
  - Given: 10 presses of Space in 1 second (100ms apart)
  - When: each press calls request_debounce("pause_toggle")
  - Then: first returns false, 2nd-6th (within 250ms) return true, 7th+ may return false if 250ms window passed
  - Edge cases: presses exactly at 250ms boundaries

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/input/debounce_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 must be DONE
- Unlocks: None
