# Code Review: Story 004 — Day Transition Event and Auto-Pause

**Date**: 2026-05-23
**Reviewer**: code-review skill + godot-gdscript-specialist + qa-tester

**Files Reviewed**:
- `src/systems/tick_system.gd` (166 lines)
- `tests/unit/tick/day_transition_test.gd` (161 lines)

## Test Results

All 7 tests pass in 369ms:
- `test_day_transition_at_boundary` — PASS (AC-1)
- `test_overflow_discarded_at_boundary` — PASS (AC-2)
- `test_manual_advance_triggers_day_transition` — PASS (AC-3)
- `test_no_accumulation_after_day_pause` — PASS (AC-4)
- `test_get_current_day_returns_incremented_value` — PASS (AC-5)
- `test_manual_advance_multi_day` — PASS (supplementary: single day crossing via manual)
- `test_day_transition_before_ticks_advanced` — PASS (signal ordering contract)

## ADR Compliance: COMPLIANT

ADR-0001 fully satisfied:
- `_accumulate_ticks()` uses `while tick_count >= TICKS_PER_DAY` loop — matches ADR spec
- `day_transition.emit(1)` fires within the loop — matches ADR spec
- `set_pause(true)` called on day boundary — matches ADR spec
- `ticks_advanced` fires after day transitions — matches ADR spec
- `advance_ticks_manual()` has its own while loop — matches ADR spec
- MAX_TICKS_PER_FRAME cap enforced — matches ADR spec
- No ADR-rejected patterns used

## Testability: TESTABLE

All 5 ACs map to distinct test functions with coverage. All test hooks publicly exposed and accessible from tests.

**Gaps:**
- `pause_state_changed` signal never asserted in day transition tests — downstream systems (audio, UI) may subscribe to it
- `is_processing()` state not directly asserted in AC-4 test (only indirectly verified via tick_count unchanged)
- No test for multi-day crossing (2+ days in one call via `advance_ticks_manual`)
- No test for `advance_ticks_manual(0)` or `advance_ticks_manual(-1)`
- Tests directly access `_tick_count` private member — works today but fragile if storage model changes. Suggest adding a test-only setter like `func set_tick_count(value: int)` following the existing `set_tick_remainder()` pattern
- Test name `test_no_accumulation_after_day_pause` misleading — tests that `_process()` is a no-op when paused, not that the engine stopped calling `_process()`

## Standards Compliance: 4/6

| Check | Status | Notes |
|-------|--------|-------|
| Public methods/classes have doc comments | PASS | Both `_accumulate_ticks` and `advance_ticks_manual` have doc comments |
| Cyclomatic complexity under 10 per method | PASS | Both methods have ~3 branches each |
| No method exceeds 40 lines | PASS | `_accumulate_ticks` is 7 lines, `advance_ticks_manual` is 9 lines |
| Dependencies injected | FAIL | Autoload singleton — authorized by ADR-0001 |
| Config values from data files | FAIL | Constants hardcoded — authorized by ADR-0001 and GDD |
| Systems expose interfaces | PASS | Public getters + signals |

## Architecture: MINOR ISSUES

1. **Code duplication** (lines 139-143 vs 160-164): The while-loop day transition body is a 5-line exact copy between `_accumulate_ticks()` and `advance_ticks_manual()`. Both do `_tick_count -= TICKS_PER_DAY`, `_current_day += 1`, `day_transition.emit(1)`, `set_pause(true)`. Maintenance risk — if one loop gets updated and the other doesn't, they diverge.

## SOLID: COMPLIANT

SRP (one responsibility per method), OCP (signal-based extension), ISP (narrow interfaces), DI (ADR-authorized Autoload). LSP N/A (no type hierarchy).

## Engine Specialist Findings (godot-gdscript-specialist)

1. **`day_transition.emit(1)` hardcoded** (tick_system.gd:142,163): The signal parameter is `days_elapsed: int` which semantically means "the number of days advanced." If a single call crosses 2+ days via the while loop, the signal fires multiple times with `1` each, not once with the actual count. **Bug** — signal payload doesn't match its declared purpose.
2. **Private member `_tick_count` accessed directly in tests** (day_transition_test.gd:27,58,80, etc.): Works in GDScript but creates tight coupling to implementation details.
3. **Closure-mutating-array pattern** in tests: `var event_order := []` with `.append()` works but fragile for future readers.

## Required Changes

1. **Fix `day_transition` signal emission** (tick_system.gd:142,163) — Currently emits `1` every iteration. Should either:
   - Count iterations and emit once after the loop with the total count, OR
   - Keep per-iteration emissions but document that `days_elapsed` is always `1` per emission (days count = number of emissions)
   Option 1 (emit once with count) is cleaner and matches the signal's semantic intent.

2. **Extract duplicated while-loop** into a private helper to eliminate the 5-line copy between `_accumulate_ticks()` and `advance_ticks_manual()`.

## Suggestions

1. Add `test_multi_day_crossing` — test `advance_ticks_manual(2100)` from `tick_count = 50` to exercise 2+ day boundaries
2. Add `test_manual_zero_cost` — verify `advance_ticks_manual(0)` behavior
3. Add `test_manual_negative_cost_ignored` — verify `advance_ticks_manual(-1)` returns early
4. Add `pause_state_changed` signal assertion to day transition tests
5. Add `is_processing()` assertion to the AC-4 test
6. Add a test-only setter for `_tick_count` to avoid direct private-member access
7. Rename `test_no_accumulation_after_day_pause` to `test_process_is_noop_when_paused` to reflect actual verification

## Fix Log

| # | Change | File | Status |
|---|--------|------|--------|
| 1 | Extracted `_advance_days() -> int` helper — counts iterations, returns day count | `src/systems/tick_system.gd:136-143` | FIXED |
| 2 | Rewrote `_accumulate_ticks()` to use `_advance_days()`, emits `day_transition(days)` once | `src/systems/tick_system.gd:146-152` | FIXED |
| 3 | Rewrote `advance_ticks_manual()` to use `_advance_days()`, emits `day_transition(days)` once | `src/systems/tick_system.gd:164-172` | FIXED |
| 4 | Updated `test_manual_multi_day_overflow_on_large_cost` — asserts 1 emission with value 2 | `tests/unit/tick/manual_advancement_test.gd:112-126` | FIXED |

All 42 tests pass across 4 suites in 1064ms.

## Verdict: CHANGES APPLIED — APPROVED

Both required fixes were applied post-review by godot-gdscript-specialist:
1. `day_transition.emit(1)` → `_advance_days()` returns actual count, emitted once with `days`
2. Duplicated while-loop extracted into shared `_advance_days()` helper
3. Existing multi-day test updated to assert correct behavior (1 emission, value = 2)
