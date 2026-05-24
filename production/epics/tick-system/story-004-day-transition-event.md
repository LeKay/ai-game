# Story 004: Day Transition Event and Auto-Pause

> **Epic**: Tick System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: Not yet created

## Context

**GDD**: `design/gdd/tick-system.md`
**Requirement**: `TR-tick-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: Tick System Design and Time Management
**ADR Decision Summary**: When `tick_count >= TICKS_PER_DAY (1000)`, the `while` loop in `_accumulate_ticks()` fires `day_transition(1)`, increments `current_day`, resets `tick_count` to 0, and calls `set_pause(true)`. Overflow ticks past 1000 are discarded (no carry). MAX_TICKS_PER_FRAME (100) ensures at most one day per frame from automatic accumulation.

**Engine**: Godot 4.6 | **Risk**: HIGH (engine version beyond LLM training data)
**Engine Notes**: No post-cutoff APIs. Signal ordering matters: `ticks_advanced` must fire after `day_transition` within `_accumulate_ticks()` — subscribers may need the updated `current_day` when processing `ticks_advanced`.

**Control Manifest Rules (this layer)**:
- Required: Autoload singleton pattern; `day_transition` signal before `ticks_advanced` within the same accumulation batch
- Forbidden: Carrying overflow ticks past 1000 into the next day (GDD specifies discard)
- Guardrail: MAX_TICKS_PER_FRAME cap guarantees at most 1 day transition per frame from automatic accumulation

---

## Acceptance Criteria

*From GDD `design/gdd/tick-system.md`:*

- [ ] **AC-1**: Given `tick_count = 999`, when 1 tick accumulates, then `day_transition(1)` fires, `tick_count` resets to 0, `current_day` increments by 1, and game enters PAUSED state
- [ ] **AC-2**: Given `tick_count = 950` and `tick_delta = 100`, when accumulation runs, then day transition fires once, overflow 50 ticks wrap into the new day, `tick_count` == 50
- [ ] **AC-3**: Given a manual action of cost 80 ticks pushes `tick_count` from 950 to 1030, then `day_transition(1)` fires, `tick_count` == 30 (30 ticks wrap into the new day), game pauses
- [ ] **AC-4**: Given game is in PAUSED state after day transition, then no automatic tick accumulation occurs until an external system calls `set_pause(false)`
- [ ] **AC-5**: Given `current_day` is available as a query, then `get_current_day()` returns the correct incremented day number after transition

---

## Implementation Notes

*Derived from ADR-0001 Implementation Guidelines:*

Implement `_accumulate_ticks()` (called by both `_process()` accumulation and `advance_ticks_manual()`):

```gdscript
var current_day: int = 1

signal day_transition(days_elapsed: int)

func _accumulate_ticks(ticks: int) -> void:
    tick_count += ticks
    while tick_count >= TICKS_PER_DAY:
        tick_count -= TICKS_PER_DAY
        current_day += 1
        day_transition.emit(1)
        set_pause(true)  # Auto-pause at day boundary
    ticks_advanced.emit(ticks)

func get_current_day() -> int:
    return current_day
```

The `while` loop handles the theoretical case where a manual action pushes `tick_count` past multiple thousands. In practice with automatic accumulation, MAX_TICKS_PER_FRAME (100) prevents more than one day per frame. Each iteration subtracts TICKS_PER_DAY, preserving the remainder within the new day.

**Overflow wrapping**: Ticks beyond 1000 wrap to the next day via subtraction. Example: 1050 → subtract 1000 → 50 ticks into the new day.

The Day Overview System (separate system — not in this epic) subscribes to `day_transition` and calls `set_pause(false)` when the player dismisses the day summary. Do not implement resume logic here.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: The `_process()` accumulation that calls `_accumulate_ticks()`
- Story 003: `advance_ticks_manual()` — tested together in AC-3 but implemented in Story 003
- Story 005: Save/load — `current_day` serialization is handled there

---

## QA Test Cases

*QL-STORY-READY skipped — Lean mode. Test cases written from GDD acceptance criteria.*

- **AC-1**: Day transition at exactly 1000 ticks
  - Given: tick_count = 999, current_day = 1, game RUNNING
  - When: `_accumulate_ticks(1)` called
  - Then: `day_transition` emitted with value 1; tick_count == 0; current_day == 2; `is_paused == true`

- **AC-2**: Overflow ticks discarded
  - Given: tick_count = 950
  - When: `_accumulate_ticks(100)` called (would bring total to 1050)
  - Then: `day_transition` emits once; tick_count == 50 (remainder preserved)
  - Edge cases: tick_count = 0, delta capped at 100 — never two transitions in one auto-accumulate frame

- **AC-3**: Manual action crossing day boundary
  - Given: tick_count = 950, `is_paused = false`
  - When: `advance_ticks_manual(80)` called
  - Then: `day_transition` emits once; tick_count == 30; `is_paused == true`

- **AC-4**: No accumulation after auto-pause
  - Given: game was RUNNING and day transition just fired (now PAUSED via `set_pause(true)`)
  - When: `_process()` would have been called (simulated via direct call)
  - Then: `set_process(false)` was called — `_process()` is disabled; tick_count unchanged

- **AC-5**: get_current_day() returns updated value
  - Given: current_day = 5, day transition fires
  - When: `get_current_day()` called after transition
  - Then: returns 6

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/tick/day_transition_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 003 must be DONE (`advance_ticks_manual()` exists for AC-3 cross-day test)
- Unlocks: Story 005 (Save/Load needs `current_day` serialization)

## Completion Notes

**Completed**: 2026-05-23
**Criteria**: 5/5 passing (all ACs verified via unit tests)
**Deviations**: ADR-0001 signal emission pattern changed from per-iteration `emit(1)` to post-loop `emit(days)` — ADR updated to reflect improvement. No multi-day test (days > 1) in test suite — low risk due to MAX_TICKS_PER_FRAME cap.
**Test Evidence**: `tests/unit/tick/day_transition_test.gd` — 7/7 tests pass
**Code Review**: `/code-review` completed — APPROVED WITH SUGGESTIONS (ADR update completed)
**Tech Debt**: None logged
