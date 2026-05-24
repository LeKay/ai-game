# Story 003: Manual Action Tick Advancement

> **Epic**: Tick System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/tick-system.md`
**Requirement**: `TR-tick-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: Tick System Design and Time Management
**ADR Decision Summary**: `advance_ticks_manual(cost: int)` bypasses `_process()` and directly increments `tick_count`, then emits `ticks_advanced(cost)`. It works regardless of pause state — a paused world advances by the action cost, then re-freezes. Manual action cost is never modified by speed multiplier.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: No post-cutoff APIs. Signal emission in a paused state (where `set_process(false)` is active) is safe — signals are independent of `_process()`.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern
- Forbidden: Applying speed_multiplier to manual action costs
- Guardrail: Day transition logic (`while tick_count >= TICKS_PER_DAY`) must also run inside `advance_ticks_manual()` — do not skip it

---

## Acceptance Criteria

*From GDD `design/gdd/tick-system.md`:*

- [ ] **AC-1**: Given game is PAUSED, when player performs a manual action costing 80 ticks, then `tick_count` increases by exactly 80 and `ticks_advanced(80)` fires
- [ ] **AC-2**: Given game is PAUSED after a manual action, when action completes, then pause state remains PAUSED (manual action does not unpause)
- [ ] **AC-3**: Given game is RUNNING at 2x speed, when player performs a manual action costing 80 ticks, then action costs exactly 80 ticks (speed multiplier does not affect manual action cost)
- [ ] **AC-4**: Given 10 manual actions are called in one frame each costing 10 ticks, then `tick_count` increases by 100 total and `ticks_advanced` fires 10 times with value 10

---

## Implementation Notes

*Derived from ADR-0001 Implementation Guidelines:*

Add to TickSystem (alongside Story 001/002 implementation):

```gdscript
func advance_ticks_manual(cost: int) -> void:
    tick_count += cost
    ticks_advanced.emit(cost)
    while tick_count >= TICKS_PER_DAY:
        tick_count -= TICKS_PER_DAY
        current_day += 1
        day_transition.emit(1)
```

The day transition `while` loop must be present in `advance_ticks_manual()` — a manual action costing more than 1000 ticks can push through a day boundary. Each day transition also sets pause state via `set_pause(true)`.

`advance_ticks_manual()` is called by the Player Character system's `start_action()` method (see ADR-0007). The Tick System does not validate cost values — callers are responsible for providing correct costs from the GDD's action cost table.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Automatic `_process()` tick accumulation
- Story 004: Day transition event handling inside `_accumulate_ticks()` (automatic path); `current_day` increment and auto-pause from day boundary

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Manual action works while paused
  - Given: `is_paused = true`, tick_count = 0
  - When: `advance_ticks_manual(80)` called
  - Then: tick_count == 80; `ticks_advanced` emitted once with value 80
  - Edge cases: tick_count at 950 + manual cost 80 = day transition fires (covered by Story 004 tests)

- **AC-2**: Pause state preserved after manual action
  - Given: `is_paused = true`
  - When: `advance_ticks_manual(80)` called
  - Then: `is_paused` still true; `pause_state_changed` not emitted

- **AC-3**: Speed multiplier has no effect on manual cost
  - Given: `speed_multiplier = 2.0`, `is_paused = false`
  - When: `advance_ticks_manual(80)` called
  - Then: tick_count increases by exactly 80 (not 160)

- **AC-4**: Multiple manual actions accumulate correctly
  - Given: tick_count = 0
  - When: `advance_ticks_manual(10)` called 10 times
  - Then: tick_count == 100; `ticks_advanced` emitted 10 separate times each with value 10

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/tick/manual_advancement_test.gd` — must exist and pass

**Status**: [x] Created and passing — 10 tests, 0 failures

---

## Dependencies

- Depends on: Story 002 must be DONE (pause state `is_paused` implemented; `ticks_advanced` signal exists)
- Unlocks: Story 004 (Day Transition needs `advance_ticks_manual()` to test cross-day manual actions)

---

## Completion Notes
**Completed**: 2026-05-23
**Criteria**: 4/4 passing (no deferred items)
**Deviations**: None
**Test Evidence**: Logic: test file at tests/unit/tick/manual_advancement_test.gd (10 tests, 0 failures)
**Code Review**: Skipped — lean mode
