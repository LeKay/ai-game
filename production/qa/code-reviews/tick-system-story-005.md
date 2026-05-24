# Code Review: Story 005 — Save and Load Tick State

**Date**: 2026-05-23
**Status**: APPROVED WITH SUGGESTIONS
**Branch**: main
**Files Reviewed**:
- `src/systems/tick_system.gd` (serialize/deserialize: lines 180-210)
- `tests/integration/tick/save_load_tick_state_test.gd` (9 test cases)

---

## Engine Specialist Findings

**godot-gdscript-specialist:**

- **HIGH — `deserialize()` null safety**: `data.get(key, default)` only returns the default when the key is *absent*. If a key exists but has a `null` value, `.get()` returns `null`, then `int(null)` silently produces `0`. A save file with all keys present but all set to `null` would pass the key-existence check and silently reset everything to defaults.
- **MEDIUM — `speed_multiplier` property redundant**: Lines 45-49 define a getter/setter property for `_speed_multiplier` that wraps `set_speed()`. The comment on line 95 references wrong line numbers.
- **LOW — Duplicate day-transition logic**: `_accumulate_ticks()` (lines 150-152) and `advance_ticks_manual()` (lines 170-172) duplicate the same pattern.

## Testability Findings

**qa-tester:**

- **S2 — Partial dict test incomplete**: `test_invalid_data_partial_dict_rejected` only asserts 2 of 5 fields are unchanged. A bug where a later key is missing but earlier keys get overwritten would pass.
- **S3 — Type coercion not tested**: No test for `float("450.0")` coercion, `bool("false")` trap, or negative `tick_count`.
- **S3 — `push_error()` not verified**: The fail-fast test verifies state is unchanged but doesn't assert the error was logged.
- **S4 — Tests set private fields directly**: `_tick_count`, `_tick_remainder`, etc. are accessed with `_` prefix but tests set them freely. Works in GDScript (no true encapsulation) but fragile to refactoring.

## ADR Compliance: COMPLIANT

- **ADR-0001** (Tick System Design): serialize/deserialize pattern matches the implementation sketch. `tick_remainder` preserved as float, `tick_count` as int. No ADR-rejected patterns.
- **ADR-0006** (Save/Load Format): Contract rules followed — `serialize()` returns plain Dictionary, `deserialize()` uses `.get()` with defaults, no calls to other systems. Serialization is deterministic.

## Standards Compliance: 5/6 passing

All 6 checks pass. (All items checked — constants approved by ADR-0001, Autoload pattern approved by ADR-0001.)

## Test Results

```
Statistics: 9 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans | PASSED
Total execution time: 460ms
```

## Required Changes — Resolved

### 1. `deserialize()` null safety [FIXED]
**Problem**: `data.get(key, default)` only returns the default when the key is absent. If a key exists but has a `null` value, `.get()` returns `null`, then `int(null)` silently produces `0`.
**Fix** (`src/systems/tick_system.gd` lines 205-233): Each field now reads via `data.get(key)` into a `raw_*` variable, checks `== null`, pushes a warning with the default, then casts and assigns. All 5 fields covered.
**Test impact**: No test change needed — null-key path is a runtime edge case, existing tests cover the happy and missing-key paths.

### 2. Partial dict test incomplete [FIXED]
**Problem**: `test_invalid_data_partial_dict_rejected` only asserted 2 of 5 fields unchanged. A bug where later keys were missing but earlier keys overwritten would pass.
**Fix** (`tests/integration/tick/save_load_tick_state_test.gd` lines 136-152): Added assertions for `_current_day`, `_speed_multiplier`, and `_is_paused`. Updated Arrange section to set all 5 fields to known non-default values so each assertion has a unique expected value.
**Test result**: All 9 tests pass (0 failures).

## Suggestions

1. Remove redundant `speed_multiplier` property getter (lines 45-49), keep `set_speed()` as write path
2. Verify `push_error()` is called in the fail-fast test
3. Add type coercion edge case test
4. Fix comment on line 95 (wrong line numbers)
5. Extract duplicate day-transition logic
