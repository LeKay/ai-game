# QA Plan — Sprint 001 (2026-05-20), Tick System Subset

**Sprint**: 001
**Date**: 2026-05-21
**Systems**: tick-system (TICK-01 only)
**Stories**: 1 Logic story
**Reason for subset**: TICK-02 through TICK-05 not yet implemented — no test files exist.

## Test Evidence Matrix

| # | Story | Type | Automated Test | Manual Test | Location |
|---|-------|------|---------------|-------------|----------|
| 1 | TICK-01: Tick Accumulator Core | Logic | Unit test (exists) | — | `tests/unit/tick/tick_accumulator_test.gd` |

## Smoke Check: Tick System

| Trigger | What to Verify | Location |
|---------|---------------|----------|
| After TICK-01 tests pass | 100s at 1x = 1000 ticks; lag spike clamped; remainder carry; signal emission | Run unit test suite in headless mode |

## Coverage Summary

| Type | Count | Required Evidence |
|------|-------|-------------------|
| Logic | 1 | Unit test (BLOCKING) |
| Integration | 0 | N/A |
| Visual/Feel | 0 | N/A |
| UI | 0 | N/A |
| Config/Data | 0 | N/A |

## Acceptance Criteria (In-Scope)

From GDD `design/gdd/tick-system.md`:

| AC | Story | Test | Status |
|----|-------|------|--------|
| AC-1: 100s at 1x = 1000 ticks (±1 frame) | TICK-01 | `test_tick_accumulator_hundred_seconds_thousand_ticks` | COVERED |
| AC-6: Lag spike > 100 clamped to 100 | TICK-01 | `test_tick_accumulator_lag_spike_clamped_to_100` | COVERED |

**Out of scope this cycle**: AC-2 through AC-5, AC-7 (belong to TICK-02 through TICK-05).

## Entry Criteria

- [x] Sprint 001 has QA plan
- [x] TICK-01 implementation exists (`src/systems/tick_system.gd`)
- [x] TICK-01 test file exists (`tests/unit/tick/tick_accumulator_test.gd`)
- [ ] Unit test suite passes in headless mode (needs execution)

## Exit Criteria

- [ ] TICK-01 unit tests all pass
- [ ] Smoke check passes
- [ ] Code review verdict: APPROVED or APPROVED WITH SUGGESTIONS
- [ ] QA verdict: APPROVED or NOT APPROVED (partial cycle)

## Notes

- Code review for TICK-01 test: **APPROVED WITH SUGGESTIONS** (3 fix log items verified)
- Sprint DoD requires all Logic stories have passing tests — this partial cycle does not satisfy the full sprint DoD
- TICK-02 through TICK-05 tests should be created as part of a subsequent `/team-qa` run once implementations exist
