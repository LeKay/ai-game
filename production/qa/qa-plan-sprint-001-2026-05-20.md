# QA Plan — Sprint 001 (2026-05-20)

**Sprint**: 001
**Date**: 2026-05-20
**Systems**: tick-system, resource-system, input-system
**Stories**: 15 (12 Logic, 3 Integration)

## Test Evidence Matrix

| # | Story | Type | Automated Test | Manual Test | Location |
|---|-------|------|---------------|-------------|----------|
| 1 | Tick 001: Tick Accumulator Core | Logic | Unit test | — | `tests/unit/tick-system/tick_accumulator_test.gd` |
| 2 | Tick 002: Speed Modes and Pause | Logic | Unit test | — | `tests/unit/tick-system/speed_modes_test.gd` |
| 3 | Tick 003: Manual Action Advancement | Logic | Unit test | — | `tests/unit/tick-system/manual_advance_test.gd` |
| 4 | Tick 004: Day Transition Event | Logic | Unit test | — | `tests/unit/tick-system/day_transition_test.gd` |
| 5 | Tick 005: Save and Load Tick State | Integration | Integration test | Smoke check | `tests/integration/tick-system/save_load_test.gd` |
| 6 | Resource 001: JSON File Loading | Logic | Unit test | — | `tests/unit/resource-system/json_loading_test.gd` |
| 7 | Resource 002: Schema Validation | Logic | Unit test | — | `tests/unit/resource-system/schema_validation_test.gd` |
| 8 | Resource 003: Dictionary Cache and O(1) Lookup | Logic | Unit test | — | `tests/unit/resource-system/dictionary_cache_test.gd` |
| 9 | Resource 004: Category System and Filtering | Logic | Unit test | — | `tests/unit/resource-system/category_filtering_test.gd` |
| 10 | Resource 005: Version Migration and Deprecated | Integration | Integration test | Smoke check | `tests/integration/resource-system/version_migration_test.gd` |
| 11 | Input 001: Input Context Stack and Action Dispatch | Logic | Unit test | — | `tests/unit/input-system/context_stack_test.gd` |
| 12 | Input 002: Debounce System | Logic | Unit test | — | `tests/unit/input-system/debounce_system_test.gd` |
| 13 | Input 003: Action Rebinding and Persistence | Logic | Unit test | — | `tests/unit/input-system/action_rebinding_test.gd` |
| 14 | Input 004: UI Context Transition | Integration | Integration test | — | `tests/integration/input-system/ui_context_transition_test.gd` |
| 15 | Input 005: Input Discard Logic | Logic | Unit test | — | `tests/unit/input-system/input_discard_test.gd` |

## Test Naming Conventions

- **Files**: `[system]_[feature]_test.gd`
- **Functions**: `test_[scenario]_[expected_result]`
- **Groups**: `func _test_[system]_group() -> void`

## Coverage Summary

| Type | Count | Required Evidence |
|------|-------|-------------------|
| Logic | 12 | Unit test per story (BLOCKING) |
| Integration | 3 | Integration test per story + smoke checks where marked (BLOCKING) |
| Visual/Feel | 0 | N/A |
| UI | 0 | N/A |
| Config/Data | 0 | N/A |

## Smoke Checks

| Trigger | What to Verify | Location |
|---------|---------------|----------|
| After Tick 005 (Save/Load) | Game starts, loads saved tick state, values match | `production/qa/smoke-2026-05-20.md` |
| After Resource 005 (Version Migration) | Game loads old-format resource files, migrates transparently | `production/qa/smoke-2026-05-20.md` |

## Acceptance Criteria (Sprint-Level)

1. All 12 unit tests pass in headless mode (`--headless --unit-test`)
2. All 3 integration tests pass in headless mode
3. Both smoke checks pass in full engine mode (no headless)
4. No test warnings or deprecation notices
5. Test execution time < 30 seconds total

## Notes

- All logic stories are fully automatable — no manual testing required beyond smoke checks
- Integration stories cover cross-system behavior (save/load persistence, version migration, UI context switching)
- No Visual/Feel or Config/Data stories in this sprint, so no screenshot/evidence pipeline needed
