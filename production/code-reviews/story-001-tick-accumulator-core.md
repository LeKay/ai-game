# Code Review: Tick System Core (Story 001)

**Story**: `production/epics/tick-system/story-001-tick-accumulator-core.md`
**Files**: `src/systems/tick_system.gd`, `tests/unit/tick/tick_accumulator_test.gd`
**Date**: 2026-05-21 (re-review — prior fixes verified)
**Verdict**: APPROVED WITH SUGGESTIONS

---

## Engine Specialist Findings: CLEAN

All APIs stable in Godot 4.6. No deprecated APIs used.

| # | Line | Issue | Severity |
|---|------|-------|----------|
| 1 | 63 | `ProjectSettings.has_setting("autoload/TickSystem")` — autoload registration may not be reflected in ProjectSettings during runtime headless/CI. Consider `get_node_or_null("/root/TickSystem")` as primary check. | Warning |
| 2 | 33 | `speed_multiplier` property has no `@export` annotation — designers cannot tune it in inspector. Intentional if code-only, but worth confirming. | Info |

---

## Testability: TESTABLE

### Test file health

| # | Location | Issue | Severity |
|---|----------|-------|----------|
| 1 | Lines 43-75 | Three FPS tests (30/60/144) are redundant — they test the same frame-rate-independence invariant. | Info |
| 2 | Line 24 | `_make_system()` writes to private `_is_paused` — seam hole if field visibility changes. TODO comment ties to Story 002. | Info |

### QA test cases from story — mapping

| QA Case | Test Exists | Testable? |
|---------|-------------|-----------|
| AC-1: 100s at 1x = 1000 ticks | Yes (line 30) | Yes |
| AC-1 variant: 30/60/144fps | Yes (lines 43-75) | Yes |
| AC-2: Lag spike clamping | Yes (lines 80-93) | Yes |
| AC-3: Signal emission | Yes (lines 138-180) | Yes |
| AC-4: Remainder carry | Yes (lines 185-210) | Yes |

Prior BLOCKING fix verified: `system2.tick_count` → `system2.get_tick_count()` (line 93). Prior WARNING fix verified: `assertAlmostEqual` on float fmod result (line 210).

---

## ADR Compliance: COMPLIANT

**ADR-0001**: Tick System Design and Time Management — fully followed.

| Aspect | ADR Spec | Implementation | Verdict |
|--------|----------|----------------|---------|
| Accumulation formula | `delta × 10 × speed_multiplier` | Line 76: `delta * TICKS_PER_SECOND_BASE * speed_multiplier` | COMPLIANT |
| Casting | `int(raw_ticks)` | `floori(raw_ticks)` | Minor deviation — more defensive for negative values |
| Remainder formula | `fmod(raw_ticks, 1.0)` | Line 80: `fmod(raw_ticks, 1.0)` | COMPLIANT |
| Clamping | `clampi(int(raw_ticks), 0, MAX_TICKS_PER_FRAME)` | Line 79: `clampi(floori(raw_ticks), 0, MAX_TICKS_PER_FRAME)` | COMPLIANT |
| Autoload pattern | Explicitly approved | `class_name TickSystem` + `_enter_tree` check | COMPLIANT |
| Signals | `ticks_advanced(delta_ticks: int)` | Line 22: `signal ticks_advanced(delta_ticks: int)` | COMPLIANT |
| `_process` usage | Required | Line 72: `func _process(delta: float) -> void` | COMPLIANT |
| No OS clock | Forbidden | No `OS.get_…` calls present | COMPLIANT |

---

## Standards Compliance: 5/6 passing

| Check | Result |
|-------|--------|
| Public methods/classes have doc comments | PASS — `_process()` (line 70) and `_accumulate_ticks()` (line 86) have doc comments (Fix 1 from prior review) |
| Cyclomatic complexity under 10 | PASS — `_process()` complexity = 3 (delta clamp, raw_ticks formula, conditional emit) |
| No method exceeds 40 lines | PASS — longest method is `_process()` at 12 lines |
| Dependencies injected | FAIL (but ADR-0001 explicitly approves Autoload pattern for infrastructure singletons) |
| Config values loaded from data files | PASS — all values are const on the class (acceptable for a deterministic accumulator) |
| Systems expose interfaces | PASS — public API via signals + query methods, not concrete dependencies |

---

## Architecture: MINOR ISSUES

| # | Line | Issue |
|---|------|-------|
| 1 | 25-29 | `_tick_count` uses bare `var` + separate `func get_tick_count()`. Inconsistent with `speed_multiplier` which uses GDScript property syntax (`var name: type: get/set`). Prefer property syntax for both or accept the inconsistency. |
| 2 | 54-55 | `set_tick_remainder()` is a test seam with no production caller. Acceptable for Story 001 but should be removed when Story 005 (save/load) implements its own persistence logic. |
| 3 | 61-67 | `_enter_tree` fatal check is correct for Autoload registration. Consider adding a `_ready` fallback in case `_enter_tree` check passes but the Autoload is somehow unregistered later. |

---

## SOLID: COMPLIANT

- **Single Responsibility**: PASS — TickSystem does one thing: accumulate ticks.
- **Open/Closed**: `speed_multiplier` clamps negatives to 0.0 (line 39-40). Extendable only via modification of the setter body. Acceptable for current scope.
- **Interface Segregation**: PASS — public API is small and focused (3 queries, 1 setter, 1 signal).
- **Dependency Inversion**: Direct `ProjectSettings` dependency (line 63). Accepted by ADR-0001 for Autoloads. No abstraction needed at this scale.
- **Liskov Substitution**: N/A — no inheritance hierarchy.

---

## Game-Specific Concerns

| Concern | Result |
|---------|--------|
| Frame-rate independence | PASS — tested at 30/60/144fps |
| No allocations in hot paths | PASS — `_process()` allocates 0 objects |
| Null/empty state handling | PASS — negative delta clamped to 0, NaN delta produces 0 ticks |
| Performance budget 0.1ms | PASS — ~5 float ops per frame |
| Resource cleanup | PASS — `_enter_tree` validates autoload registration |

---

## Positive Observations

- **Clean edge-case handling**: Negative delta, NaN delta, and zero delta are all handled gracefully in `_process()`.
- **Test file quality**: Consistent Arrange/Act/Assert structure, descriptive test names following the convention, factory helper `_make_system()` provides clean isolation.
- **Signal architecture**: `ticks_advanced` fires once per frame with batched count, not once per tick — avoids signal spam (ADR performance note validated).
- **fmod remainder**: Chose `fmod(raw_ticks, 1.0)` over `raw_ticks - tick_delta` to prevent drift — correctly implemented and documented.
- **No post-cutoff APIs**: All APIs (`_process`, `clampi`, `floori`, `fmod`) are stable since Godot 1.0.

---

## Required Changes

None. All prior required changes verified as applied.

---

## Suggestions

- **Line 21**: Consider adding `speed_changed` signal stub (even if unimplemented) as a TODO — the ADR declares it and future stories will implement it. Makes the interface visible now.
- **Lines 43-75**: Consolidate 30/60/144fps tests into a parameterized test or single test with multiple delta values. Same invariant, less duplication.
- **Line 24**: Replace direct `_is_paused = false` access with a factory flag or `test_mode` property on TickSystem when Story 002 is complete.

---

## Verdict: APPROVED WITH SUGGESTIONS

All prior required changes verified. No new blocking or required changes found. Suggestions are non-blocking improvements for future refinement.

---

## Fix Log

| # | Change | File | Status |
|---|--------|------|--------|
| 1 | Added doc comments to `_process()` and `_accumulate_ticks()` | `src/systems/tick_system.gd:70-87` | VERIFIED |
| 2 | `system2.tick_count` → `system2.get_tick_count()` | `tests/unit/tick/tick_accumulator_test.gd:93` | VERIFIED |
| 3 | `GDTest.assertEqual(..., 0.199)` → `GDTest.assertAlmostEqual(..., 0.199, 0.001)` | `tests/unit/tick/tick_accumulator_test.gd:210` | VERIFIED |

All 3 required changes verified. Post-fix verdict: **APPROVED WITH SUGGESTIONS**
