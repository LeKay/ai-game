# Code Review: Story 003 — Manual Action Tick Advancement

**Date**: 2026-05-23
**Reviewer**: code-review skill + godot-gdscript-specialist + qa-tester

**Files Reviewed**:
- `src/systems/tick_system.gd` (157 lines)
- `tests/unit/tick/manual_advancement_test.gd` (157 lines)

## Test Results

All 10 tests pass in 425ms:
- `test_initial_current_day` — PASS
- `test_initial_speed_multiplier` — PASS
- `test_manual_advancement_while_paused` — PASS
- `test_pause_state_preserved_after_manual_action` — PASS
- `test_manual_action_respects_no_speed_multiplier` — PASS
- `test_multiple_manual_actions_accumulate` — PASS
- `test_manual_day_transition_on_overflow` — PASS
- `test_manual_multi_day_overflow_on_large_cost` — PASS
- `test_manual_overflow_from_near_end_of_day` — PASS
- `test_manual_negative_cost_no_guard` — PASS

## ADR Compliance: COMPLIANT

ADR-0001 fully satisfied:
- `advance_ticks_manual()` bypasses `_process()` — correct
- Directly increments `_tick_count` and emits `ticks_advanced(cost)` — correct
- Works regardless of pause state — correct
- Manual action cost not modified by speed multiplier — correct
- Day transition `while` loop present in `advance_ticks_manual()` — correct
- Signal names match — correct
- No ADR-rejected patterns used

## Testability: TESTABLE

All test hooks publicly exposed and accessible from tests. All 4 QA test cases map to testable code paths.

**Gaps:**
- AC-2 test assertion gap — FIXED: `test_pause_state_preserved_after_manual_action` now captures `pause_state_changed` via `fired_with := [-1]` and asserts `fired_with[0] == -1`, confirming the signal was never emitted.
- Untested edge cases: zero cost, manual+auto path coexistence, `_tick_remainder` preservation after manual action
- `_make_running_system()` enables `_process`, so tests checking initial state have a live accumulator — tests pass today but could be flaky

## Standards Compliance: 4/6

| Check | Status | Notes |
|-------|--------|-------|
| Public methods/classes have doc comments | FAIL | `set_pause()` (line 101) missing doc comment |
| Cyclomatic complexity under 10 per method | PASS | `advance_ticks_manual` is ~3 branches |
| No method exceeds 40 lines | PASS | `advance_ticks_manual` is 7 lines |
| Dependencies injected | FAIL | Autoload singleton — ADR-0001 explicitly authorizes |
| Config values from data files | FAIL | Constants hardcoded — ADR-0001 and GDD specify fixed values |
| Systems expose interfaces | PASS | Public getters + signals |

## Architecture: CLEAN

Correct dependency direction, no circular deps, proper layer separation, signal-based communication, consistent with ADR-0001.

## SOLID: COMPLIANT

SRP (one reason to change), OCP (signal-based extension), ISP (narrow interfaces), DI (ADR-authorized Autoload). LSP N/A (no hierarchy).

## Engine Specialist Findings (godot-gdscript-specialist)

1. **`fmod` vs `fposmod`** (tick_system.gd:129): `fmod` preserves sign of dividend. If `raw_ticks` goes negative, `_tick_remainder` becomes negative. Use `fposmod(raw_ticks, 1.0)`. *Latent bug.*
2. **Inconsistent accessor pattern**: `_tick_count` uses private-var-then-getter while `speed_multiplier` uses Godot 4 property syntax (`get:`). Use property syntax consistently.
3. **Untyped arrays in test**: `var counts := []` should be `var counts: Array[int] = []`.

## Required Changes

1. **Guard against negative costs in `advance_ticks_manual()`** (tick_system.gd:150). Either add `if cost < 0: return` or clamp: `cost = maxi(0, cost)`.

## Fix Log

| # | Change | File | Status |
|---|--------|------|--------|
| 1 | Added doc comment to `set_pause()` | `src/systems/tick_system.gd:100` | FIXED |
| 2 | `fmod` → `fposmod` (prevent negative remainder) | `src/systems/tick_system.gd:129` | FIXED |
| 3 | Added `if cost < 0: return` guard in `advance_ticks_manual()` | `src/systems/tick_system.gd:151-152` | FIXED |
| 4 | Renamed `test_manual_negative_cost_no_guard` → `test_manual_negative_cost_ignored`; updated assertions | `tests/unit/tick/manual_advancement_test.gd:144-154` | FIXED |

All 4 fixes applied and verified. All 10 tests pass in 356ms.

## Suggestions

1. Use Godot 4 property syntax for `_tick_count`, `_current_day`, `_tick_remainder`
2. Initialize `set_process(false)` in `_make_running_system()` helper
3. Add `test_manual_zero_cost` edge case
4. Add `test_manual_auto_coexistence` to verify manual and automatic paths don't interfere

## Verdict: APPROVED WITH SUGGESTIONS
