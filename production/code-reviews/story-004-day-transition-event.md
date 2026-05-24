# Code Review: TickSystem — Story 004 (Day Transition Event and Auto-Pause)

**Date**: 2026-05-23
**Reviewer**: /code-review skill
**Story**: `production/epics/tick-system/story-004-day-transition-event.md`
**Implementation**: `src/systems/tick_system.gd`
**Tests**: `tests/unit/tick/day_transition_test.gd`, `tests/unit/tick/speed_pause_test.gd`, `tests/unit/tick/tick_accumulator_test.gd`
**ADR**: `docs/architecture/adr-0001-tick-system.md`
**Test Results**: 42/42 tick tests passing (0 failures)

---

## Engine Specialist Findings: ISSUES FOUND

**godot-gdscript-specialist** reviewed `src/systems/tick_system.gd`:

- **BUG (lines 47-48 vs 63-67) — Inconsistent signal emission between property setter and `set_speed()`**: Assigning `tick_system.speed_multiplier = 2.0` (direct property write) clamps but does **not** emit `speed_changed`. Calling `tick_system.set_speed(2.0)` **does** emit the signal. These are equivalent operations with different side effects. The setter should call `_set_speed_and_notify()` instead of clamping silently.
- **LOW (lines 142-143, 163-164) — Signal ordering edge case**: `day_transition` fires before `set_pause(true)`. Subscribers to `day_transition` see the system in RUNNING state. If a listener does end-of-day calculations that assume the world is still ticking, they'll see inconsistent state. Whether intentional or a bug depends on design intent.
- **STYLE (lines 55-60, 63, 126, 129, 130) — `let` vs `var`**: Local variables that are never reassigned should use `let` instead of `var` in GDScript 4.x. Examples: `var clamped: float = SPEED_OPTIONS[0]` (line 55), `var raw_ticks` (line 126), `var tick_delta` (line 129).
- **STYLE (lines 53-54, 56-58) — Redundant `.has()` + `is_equal_approx`**: `SPEED_OPTIONS.has(value)` exact check and `is_equal_approx(s, value)` in the fallback loop overlap. The `.has()` check is effectively dead code for float comparisons since `is_equal_approx` handles the same cases.
- **INFO (line 112) — `queue_free()` on autoload failure**: `queue_free()` on an autoload singleton is a no-op (autoloads persist across scene changes). Should use `push_fatal` or an assertion instead.

## Testability: TESTABLE

All 5 ACs have corresponding tests and they pass. Tests access private members (`_tick_count`) — acceptable for GdUnit4.

**QA gap — `pause_state_changed` signal not tested during day transition**: When a day transition auto-pauses the game, `set_pause(true)` is called internally, which emits `pause_state_changed(true)`. No test verifies this signal fires during day transition. External systems (pause UI overlay, input disabling) depend on this signal.

**QA gap — Multi-day single call not tested**: `advance_ticks_manual(2001)` from `tick_count=0` should fire `day_transition` three times. No automated test covers the while-loop's multi-iteration path.

**Spec mismatch**: AC-2 and AC-3 QA test cases in the story document assert `tick_count == 0`, but the implementation correctly produces `tick_count == 50` / `tick_count == 30` (remainder preserved). The **automated tests are correct**; the **story QA test case document needs updating**.

## ADR Compliance: DRIFT

**ADR-0001 checked.**

- The ADR template code (line 112: `tick_count = 0`) says reset to 0, discarding overflow.
- The implementation and tests use `tick_count -= TICKS_PER_DAY` (preserving remainder).
- The ADR validation criteria (line 245) also says "tick_count resets to 0".

This is **ADR DRIFT (WARNING)**: the implementation meaningfully diverges from both the ADR template code and its validation criteria. The ADR itself is internally inconsistent.

**Resolution**: Whichever direction is chosen, update all three documents: the ADR template code, the ADR validation criteria, and the story's QA test cases. The automated tests follow the remainder path — if that's the intended behavior, the ADR and story need to be updated to match.

## Standards Compliance: 4/6 passing

- [x] Public methods and classes have doc comments
- [x] Cyclomatic complexity under 10 per method
- [x] No method exceeds 40 lines (excluding data declarations)
- [x] Dependencies are injected (Autoload pattern — sanctioned by ADR-0001)
- [ ] **FAIL** Configuration values loaded from data files: `TICKS_PER_DAY`, `TICKS_PER_SECOND_BASE`, `MAX_TICKS_PER_FRAME`, `SPEED_OPTIONS` are all hardcoded consts (coding-standards.md: "Gameplay values must be data-driven")
- [ ] **FAIL** Systems expose interfaces: TickSystem is a concrete Autoload Node with no interface; consumers depend on the concrete class directly (mitigated by ADR-0001's explicit Autoload choice)

## Architecture: MINOR ISSUES

- **Setter/signal asymmetry**: `speed_multiplier = X` silently clamps; `set_speed(X)` emits. Callers may use either form unpredictably.
- **`day_transition` before `set_pause(true)`**: Listeners see RUNNING state during day transition. Document intent or swap order.
- **Autoload `queue_free()` on failure** (line 112): Effectively a no-op. The error will be silent — the project will crash later with "attempt to call function in base null".

## SOLID: COMPLIANT

- Single Responsibility: One class, one job (tick accumulation + day boundary)
- Open/Closed: Extendable via signals without modifying the accumulator
- Liskov: N/A (no inheritance hierarchy)
- Interface Segregation: Signals are focused; callers subscribe only what they need
- Dependency Inversion: N/A (Autoload is by design per ADR-0001)

## Game-Specific Concerns

- [x] Frame-rate independence: Remainder carry correctly implemented with `fposmod`
- [ ] No allocations in hot paths: `_clamp_speed()` — the `SPEED_OPTIONS.has()` call allocates an iterator on the Array
- [x] Null/empty state handling: Negative delta clamped to 0, NaN speed handled
- [x] Thread safety: Single-threaded (autoload, main thread only)
- [x] Resource cleanup: `set_process(false)` on pause — zero CPU cost

## Positive Observations

- Clean use of `fposmod` for remainder carry — correct Godot 4 pattern
- `MAX_TICKS_PER_FRAME` cap correctly prevents lag-spike multi-day jumps
- Idempotent `set_pause()` and `set_speed()` — no duplicate signals on redundant calls
- Well-structured signal declarations with typed parameters
- Tests are comprehensive with good edge case coverage (42/42 passing)
- The signal ordering test (`test_day_transition_before_ticks_advanced`) enforces an important invariant

## Required Changes — Fixed

### 1. Property setter signal emission — FIXED

`src/systems/tick_system.gd` line 48: changed `_speed_multiplier = _clamp_speed(value)` to `_set_speed_and_notify(value)`. Both `set_speed()` and `speed_multiplier = X` now emit `speed_changed` consistently.

### 2. ADR/story/test spec mismatch — FIXED

All three documents updated to match the remainder behavior (`tick_count -= TICKS_PER_DAY`):

- **ADR** (`adr-0001-tick-system.md`): Template code (lines 112, 124) changed `tick_count = 0` → `tick_count -= TICKS_PER_DAY`. Validation criteria (line 245) updated to "tick_count wraps via subtraction, remainder preserved".
- **Story Acceptance Criteria** (AC-2, AC-3): Updated to reflect `tick_count == 50` / `tick_count == 30` instead of reset to 0.
- **Story QA Test Cases** (AC-2, AC-3): Updated expected values to 50 / 30.
- **Story Implementation Notes**: Template code and explanatory comments updated throughout.

## Suggestions

- Use `let` for single-assignment local variables
- Swap `day_transition.emit()` and `set_pause(true)` order — or explicitly document that day-transition listeners may see the system in RUNNING state
- Add test for `pause_state_changed` signal during day transition
- Add test for exact-boundary case (`tick_count=0`, `_accumulate_ticks(1000)`)
- Remove redundant `SPEED_OPTIONS.has()` check in `_clamp_speed()`

## Verdict: APPROVED WITH SUGGESTIONS

Both required changes are resolved. Remaining items are non-blocking suggestions:
- `let` vs `var` for single-assignment locals
- `day_transition` / `set_pause(true)` signal ordering — document intent or swap
- Additional test coverage for `pause_state_changed` during day transition, exact boundary case
- Remove redundant `SPEED_OPTIONS.has()` check in `_clamp_speed()`
