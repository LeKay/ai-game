# Code Review: Story 003 — Manual Action Tick Advancement

**Date**: 2026-05-23
**Reviewer**: code-review skill + godot-gdscript-specialist + qa-tester

**Files Reviewed**:
- `src/systems/tick_system.gd` (157 lines)
- `tests/unit/tick/manual_advancement_test.gd` (157 lines, 10 tests)

**Story File**: `production/epics/tick-system/story-003-manual-action-advancement.md`

---

## Test Results

All 10 tests pass in 425ms:
- `test_initial_current_day` — PASS
- `test_initial_speed_multiplier` — PASS
- `test_manual_advancement_while_paused` — PASS (AC-1)
- `test_pause_state_preserved_after_manual_action` — PASS (AC-2)
- `test_manual_action_respects_no_speed_multiplier` — PASS (AC-3)
- `test_multiple_manual_actions_accumulate` — PASS (AC-4)
- `test_manual_day_transition_on_overflow` — PASS (1500 cost from 0)
- `test_manual_multi_day_overflow_on_large_cost` — PASS (2500 cost from 0)
- `test_manual_overflow_from_near_end_of_day` — PASS (950 + 80)
- `test_manual_negative_cost_no_guard` — PASS (documents negative cost behavior)

---

## ADR Compliance: COMPLIANT

**ADR-0001** (Tick System Design and Time Management) fully satisfied:
- `advance_ticks_manual()` bypasses `_process()` — correct
- Directly increments `_tick_count` and emits `ticks_advanced(cost)` — correct
- Works regardless of pause state — correct
- Manual action cost not modified by speed multiplier — correct
- Day transition `while` loop present in `advance_ticks_manual()` — correct
- Signal names match ADR specification — correct
- Autoload singleton pattern matches ADR decision — correct
- No ADR-rejected patterns used

---

## Testability: TESTABLE

All test hooks publicly exposed and accessible from tests. All 4 QA test cases map to testable code paths. No acceptance criteria are untestable.

**Gaps (non-blocking):**
- AC-2 already verified via `pause_state_changed` signal check (QA review fix applied)
- Untested edge cases: zero cost, manual+auto path coexistence, `_tick_remainder` preservation after manual action
- `_make_running_system()` enables `_process`, so tests checking initial state (tick_count=0) have a live accumulator running — tests pass today but could be flaky

---

## Standards Compliance: 4/6

| Check | Status | Notes |
|-------|--------|-------|
| Public methods/classes have doc comments | FAIL | `set_pause()` (line 101) missing doc comment |
| Cyclomatic complexity under 10 per method | PASS | `advance_ticks_manual` is ~3 branches |
| No method exceeds 40 lines | PASS | `advance_ticks_manual` is 7 lines |
| Dependencies injected | FAIL | Autoload singleton — explicitly authorized by ADR-0001 |
| Config values from data files | FAIL | Constants hardcoded — ADR-0001 and GDD specify fixed values |
| Systems expose interfaces | PASS | Public getters + signals |

Note: The 2 FAILs on DI and data-driven values are explicitly authorized by ADR-0001. Consider noting this exception in the technical preferences forbidden patterns section.

---

## Architecture: CLEAN

- Correct dependency direction (gameplay <- foundation)
- No circular dependencies
- Proper layer separation (TickSystem owns game state, UI only queries)
- Signal-based communication with all subscribers
- Consistent with ADR-0001 and established patterns from Stories 001/002
- `_process()` coexistence with `advance_ticks_manual()` works correctly

---

## SOLID: COMPLIANT

- **SRP**: TickSystem owns time accumulation; manual advancement is one reason to change
- **OCP**: Signal-based extension — new systems subscribe without modifying TickSystem
- **LSP**: N/A — no type hierarchy
- **ISP**: Narrow interfaces — callers only need `advance_ticks_manual()`, `is_paused()`, `get_current_day()`
- **DI**: ADR-authorized Autoload pattern

---

## Game-Specific Concerns

- **Frame-rate independence**: Correctly uses `delta` with remainder carry — solid
- **No allocations in hot paths**: `_process()` has zero allocations — clean
- **Null/empty state handling**: `delta < 0.0` guard present — good
- **Resource cleanup**: `_enter_tree()` autoload check present — minor convention issue below
- **`_enter_tree()` vs `_ready()`** (line 107): Autoload lifecycle check uses `_enter_tree()`. `_ready()` is more conventional for Autoloads and ensures full initialization.

---

## Engine Specialist Findings (godot-gdscript-specialist)

1. **`fmod` vs `fposmod`** (tick_system.gd:129): `fmod` preserves the sign of the dividend. If `raw_ticks` goes negative in the future, `_tick_remainder` becomes negative, causing future accumulation to lose ticks. Use `fposmod(raw_ticks, 1.0)` which always returns non-negative. *Latent bug — won't trigger under current code paths.*

2. **Inconsistent accessor pattern** (tick_system.gd:36-40 vs 44-48): `_tick_count` uses private-var-then-`get_tick_count()` getter while `speed_multiplier` uses Godot 4 property syntax (`get:`). Use property syntax consistently.

3. **Untyped arrays in test** (manual_advancement_test.gd:83, 116, 150): `var counts := []` etc. should be `var counts: Array[int] = []` for static typing.

4. **Signal assertion could use GdUnit4 built-in** (manual_advancement_test.gd:41-42): The sentinel-value pattern (`fired_with := [-1]`) works but is verbose. GdUnit4 supports `assert_signal()` which would be clearer.

---

## Positive Observations

- `advance_ticks_manual()` is a clean, 7-line implementation matching the ADR spec exactly
- Day transition `while` loop correctly handles multi-day overflow
- Test file has 10 tests covering all 4 ACs plus 6 additional edge cases
- All 10 tests pass in 425ms
- Test for documented-but-questionable behavior (`test_manual_negative_cost_no_guard`) is honest and explicit
- `set_pause()` toggles `set_process()` — zero CPU cost when paused, as ADR intended
- `_clamp_speed()` fuzzy matching is a practical approach for discrete speed options

---

## Required Changes

1. **Guard against negative costs in `advance_ticks_manual()`** (tick_system.gd:150). Either add `if cost < 0: return` at the top, or clamp: `cost = maxi(0, cost)`. The current behavior allows game progress to be undone by a negative-cost action.

---

## Suggestions

1. Replace `fmod` with `fposmod` on line 129 to prevent negative remainder accumulation
2. Add doc comment on `set_pause()` to meet coding standards
3. Use Godot 4 property syntax consistently for `_tick_count`, `_current_day`, `_tick_remainder`
4. Initialize `set_process(false)` in `_make_running_system()` helper for tests checking initial state
5. Add `test_manual_zero_cost` edge case
6. Add `test_manual_auto_coexistence` to verify manual and automatic paths don't interfere

---

## Fix Log

| # | Change | File | Status |
|---|--------|------|--------|
| 1 | Added doc comment to `set_pause()` | `src/systems/tick_system.gd:100` | FIXED |
| 2 | `fmod` → `fposmod` (prevent negative remainder) | `src/systems/tick_system.gd:129` | FIXED |
| 3 | Added `if cost < 0: return` guard in `advance_ticks_manual()` | `src/systems/tick_system.gd:151-152` | FIXED |
| 4 | Renamed `test_manual_negative_cost_no_guard` → `test_manual_negative_cost_ignored`; updated assertions | `tests/unit/tick/manual_advancement_test.gd:144-154` | FIXED |

All 4 fixes applied and verified. Post-fix verdict: **APPROVED WITH SUGGESTIONS**

## Verdict: APPROVED WITH SUGGESTIONS

The implementation correctly follows ADR-0001, all ACs pass with tests, and the architecture is clean. The only required change is a negative-cost guard.
