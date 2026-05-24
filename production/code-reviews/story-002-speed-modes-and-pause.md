# Code Review: Tick System — Story 002 (Speed Modes and Pause State Machine)

**Date**: 2026-05-21
**Reviewer**: /code-review skill
**Files**: `src/systems/tick_system.gd`, `tests/unit/tick/speed_pause_test.gd`
**Story**: `production/epics/tick-system/story-002-speed-modes-and-pause.md`
**ADR**: ADR-0001 (Tick System Design and Time Management)

## Verdict: CHANGES REQUIRED (re-review requested)

## Test Results

All 10 tests pass (426ms total):

| Test | AC | Result |
|------|-----|--------|
| test_pause_no_accumulation | AC-1 | PASS |
| test_speed_2x_50s_1000_ticks | AC-2 | PASS |
| test_speed_05x_200s_1000_ticks | AC-3 | PASS |
| test_no_duplicate_speed_signals | AC-4 | PASS |
| test_rapid_pause_toggle_stability | AC-5 | PASS |
| test_idempotent_set_pause_already_paused | AC-6 | PASS |
| test_invalid_speed_clamps_to_options | AC-7 | PASS |
| test_ticks_advanced_signal_emits_with_correct_delta | Extra | PASS |
| test_remainder_preserved_across_pause_unpause | Extra | PASS |
| test_set_pause_public_api | Extra | PASS |

## Engine Specialist Findings: ISSUES FOUND

**godot-gdscript-specialist:**

| Line | Severity | Finding |
|------|----------|---------|
| 48 | BLOCKING | `_clamp_speed()` returns `speed_multiplier` (property) instead of `_speed_multiplier` (variable). No recursion risk today (getter is passthrough), but fragile if getter logic is added later. |
| 59 | WARNING | Float equality `clamped != _speed_multiplier` is theoretically brittle. Safe here since both values are always `SPEED_OPTIONS` literals. |
| 94-96 | WARNING | `queue_free()` on autoload registration check destroys the entire tick system. `push_error()` alone is sufficient. |
| 57 | INFO | `_set_speed_and_notify()` called from one place — candidate for inlining. |

## ADR Compliance: COMPLIANT

ADR-0001 fully compliant. All patterns match: speed clamping, pause with `set_process()`, signal emissions, no OS clock, autoload singleton.

## Required Changes

### 1. Implementation — Line 48 (BLOCKING)
**File**: `src/systems/tick_system.gd:48`
**Change**: `return speed_multiplier` → `return _speed_multiplier`

In `_clamp_speed()`, returning the property instead of the backing variable is a latent recursion risk. If any logic is added to the getter, a stack overflow will occur silently.

### 2. Tests — Private field access (BLOCKING)
**File**: `tests/unit/tick/speed_pause_test.gd`
**Change**: Replace all direct assignments to `_is_paused`, `_tick_remainder`, `_speed_multiplier` with public API calls.

The test suite has 16 call sites bypassing public APIs:

| Field | Call Sites | Fix |
|-------|-----------|-----|
| `_is_paused` | Lines 18, 79, 105, 112, 115, 127, 157, 222, 228, 243 | Use `set_pause()` |
| `_tick_remainder` | Lines 19, 106, 212 | Use `set_tick_remainder()` |
| `_speed_multiplier` | Lines 79, 161, 213 | Use `set_speed()` |

**Impact**: The test suite can pass even if `set_pause()` and `set_speed()` are non-functional stubs. Only `_process()`'s early-return on `_is_paused` is actually tested.

### 3. Tests — AC-1 signal verification (WARNING)
**File**: `tests/unit/tick/speed_pause_test.gd:test_pause_no_accumulation`
**Change**: Connect to `ticks_advanced` signal and assert it does not fire during pause.

The QA test case explicitly requires "ticks_advanced not emitted" — this is not verified by the current test.

### 4. Tests — set_pause() process toggle verification (WARNING)
**File**: `tests/unit/tick/speed_pause_test.gd`
**Change**: Add assertion verifying `set_pause()` correctly calls `set_process()`.

`test_set_pause_public_api()` verifies `is_paused()` return value and signal emission, but does not assert the processing state. If `set_process()` were missing or inverted, the signal assertions would pass while the system is broken.

## Suggestions

1. Inline `_set_speed_and_notify()` into `set_speed()` (line 57).
2. Use epsilon comparison for float equality on line 59.
3. Replace `queue_free()` with `push_error()` only in `_enter_tree()` (lines 94-96).
4. Consider `class_name TickSystem` for static typing by consumers.
5. Add test for `set_speed()` called while paused.

## Positive Observations

- Clean structure with proper separation of concerns.
- Typed signals throughout.
- Idempotent guards on both `set_pause()` and `set_speed()` preventing spurious signal emissions.
- `set_process(false)` on pause achieves zero CPU cost.
- Strong test coverage — 10 test cases for 7 acceptance criteria.

## Standards Compliance: 4/6 passing

| Check | Status |
|-------|--------|
| Public methods/classes have doc comments | PASS |
| Cyclomatic complexity under 10 per method | PASS |
| No method exceeds 40 lines | PASS |
| Dependencies injected (no static singletons) | WARN — Autoload is intentional per ADR-0001 |
| Configuration values loaded from data files | PASS |
| Systems expose interfaces | PASS |

## Architecture: MINOR ISSUES

Autoload coupling is intentional and documented in ADR-0001. No architectural violations.

## SOLID: COMPLIANT

## Game-Specific Concerns

- Frame-rate independence: PASS (delta time + remainder carry)
- No allocations in `_process()`: PASS
- Negative delta handling: PASS
- Null handling: N/A — no node references

## Changes Applied

**Date**: 2026-05-21 | **Test run**: 10/10 PASS (535ms)

### 1. tick_system.gd:48 — BLOCKING
**Change**: `return _speed_multiplier` (backing variable, not property getter). Prevents latent stack overflow if getter logic is added.

### 2. speed_pause_test.gd — BLOCKING (private field access)
**Change**: Replaced all direct assignments to private fields with public API calls:

| File | Before | After |
|------|--------|-------|
| `speed_pause_test.gd:18` | `system._is_paused = false` | `system.set_pause(false)` |
| `speed_pause_test.gd:19` | `system._tick_remainder = 0.0` | `system.set_tick_remainder(0.0)` |
| `speed_pause_test.gd:28` | `system._is_paused = true` | `system.set_pause(true)` |
| `speed_pause_test.gd:78` | `system._speed_multiplier = 1.0` | `system.set_speed(1.0)` |
| `speed_pause_test.gd:104` | `system._is_paused = false` | `system.set_pause(false)` |
| `speed_pause_test.gd:105` | `system._tick_remainder = 0.0` | `system.set_tick_remainder(0.0)` |
| `speed_pause_test.gd:111-113` | manual `_is_paused` + `set_process()` | `set_pause(false)` / `set_pause(true)` |
| `speed_pause_test.gd:124` | `system._is_paused = true` | `system.set_pause(true)` |
| `speed_pause_test.gd:153` | `system._is_paused = false` | `system.set_pause(false)` |
| `speed_pause_test.gd:207` | `system._is_paused = false` | `system.set_pause(false)` |
| `speed_pause_test.gd:208` | `system._tick_remainder = 0.7` | `system.set_tick_remainder(0.7)` |
| `speed_pause_test.gd:209` | `system._speed_multiplier = 1.0` | `system.set_speed(1.0)` |
| `speed_pause_test.gd:218` | `system._is_paused = true` | `system.set_pause(true)` |
| `speed_pause_test.gd:223` | `system._is_paused = false` | `system.set_pause(false)` |
| `speed_pause_test.gd:237` | `_is_paused = false` + `set_process(false)` | `set_pause(false)` |

**Impact**: Tests now exercise the public contract. `set_pause()` and `set_speed()` logic (clamping, signal emission, `set_process()` toggle) is actually tested.

### 3. speed_pause_test.gd — WARNING (AC-1 signal verification)
**Change**: `test_pause_no_accumulation` now connects to `ticks_advanced` signal and asserts `signal_triggered[0] == false` after `_process` calls during pause.

### 4. speed_pause_test.gd — Minor cleanup
**Change**: Removed redundant `system.set_process(false)` in `test_set_pause_public_api` setup. `set_pause(false)` already enables process via its public implementation. Fixed comment that said "process enabled" when process was disabled.
